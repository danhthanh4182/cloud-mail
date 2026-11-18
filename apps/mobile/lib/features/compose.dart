import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../domain/mail.dart';
import '../design_system/components.dart';

class ComposeScreen extends StatefulWidget {
  final AppController state;
  final MailDraft? draft;
  const ComposeScreen({super.key, required this.state, this.draft});
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen>
    with WidgetsBindingObserver {
  late final MailDraft d;
  late final String identity;
  late final TextEditingController to, cc, bcc, subject, body;
  Timer? timer;
  bool sending = false, picking = false, saved = false;
  String error = '';
  AppController get s => widget.state;
  @override
  void initState() {
    super.initState();
    identity = s.scope;
    d =
        widget.draft ??
        MailDraft(accountId: s.selectedAddress ?? s.addresses.first.id);
    to = TextEditingController(text: d.to);
    cc = TextEditingController(text: d.cc);
    bcc = TextEditingController(text: d.bcc);
    subject = TextEditingController(text: d.subject);
    body = TextEditingController(text: d.body);
    for (final c in [to, cc, bcc, subject, body]) {
      c.addListener(changed);
    }
    WidgetsBinding.instance.addObserver(this);
  }

  void changed() {
    if (d.outcomeUncertain) return;
    d.to = to.text;
    d.cc = cc.text;
    d.bcc = bcc.text;
    d.subject = subject.text;
    d.body = body.text;
    if (d.sendState == 'rejected') {
      d.requestKey = '';
      d.sendState = '';
    }
    timer?.cancel();
    if (mounted) setState(() => saved = false);
    timer = Timer(const Duration(milliseconds: 650), save);
  }

  Future<void> save() async {
    timer?.cancel();
    if (identity != s.scope || !s.signedIn || !d.hasContent) return;
    try {
      await s.saveDraft(d);
      if (mounted) {
        setState(() {
          saved = true;
          error = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              s.t('Không lưu được nháp: ', 'Draft could not be saved: ') +
              e.toString(),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(save());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    for (final c in [to, cc, bcc, subject, body]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> attach() async {
    setState(() => picking = true);
    try {
      final files = await FilePicker.pickFiles();
      for (final file in files) {
        if (d.attachments.length >= 10) {
          throw const FormatException('Maximum 10 files');
        }
        final total = d.attachments.fold<int>(
          0,
          (a, b) => a + asInt(b['size']),
        );
        final size = file.lengthSync();
        if (size == null ||
            size > 5 * 1024 * 1024 ||
            total + size > 10 * 1024 * 1024) {
          throw const FormatException('Maximum 5 MB per file, 10 MB total');
        }
        final stream = file.readAsByteStream();
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in stream) {
          bytes.add(chunk);
          if (bytes.length > 5 * 1024 * 1024) {
            throw const FormatException('File exceeds 5 MB');
          }
        }
        final data = bytes.takeBytes();
        d.attachments.add({
          'filename': file.name,
          'mimeType': lookupMimeType(file.name) ?? 'application/octet-stream',
          'size': data.length,
          'content': await compute(base64Encode, data),
        });
      }
      await save();
    } catch (e) {
      if (mounted) showNotice(context, e.toString());
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> send() async {
    try {
      if (!s.addresses.any((a) => a.id == d.accountId)) {
        throw const FormatException('Choose an available sender');
      }
      final recipients = parseRecipients(to.text);
      parseRecipients(cc.text);
      parseRecipients(bcc.text);
      if (recipients.isEmpty) {
        throw const FormatException('Recipient is required');
      }
      if (!await confirm(
        context,
        s,
        s.t('Gửi thư này?', 'Send this email?'),
        '${s.t('Đến', 'To')}: ${recipients.join(', ')}\n${subject.text}',
        label: s.t('Gửi', 'Send'),
      )) {
        return;
      }
      if (!mounted) return;
      setState(() => sending = true);
      await save();
      final outcome = await s.sendDraft(d);
      if (!mounted) return;
      if (outcome == 'accepted') {
        showNotice(
          context,
          s.t(
            'Máy chủ đã chấp nhận gửi thư.',
            'The server accepted the email for sending.',
          ),
        );
        Navigator.pop(context);
      } else {
        showNotice(context, s.t('Trạng thái gửi: ', 'Send status: ') + outcome);
      }
    } catch (e) {
      if (mounted) showNotice(context, e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = d.outcomeUncertain || sending;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await save();
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('Soạn thư', 'Compose')),
          actions: [
            IconButton(
              tooltip: s.t('Đính kèm', 'Attach'),
              onPressed: locked || picking ? null : attach,
              icon: const Icon(Icons.attach_file),
            ),
            IconButton(
              tooltip: s.t('Gửi thư', 'Send email'),
              onPressed: locked || picking || !s.capabilities.safeSend
                  ? null
                  : send,
              icon: sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!s.capabilities.safeSend)
                Text(
                  s.t(
                    'Máy chủ cần API mobile mới để gửi an toàn. Bạn vẫn có thể soạn và lưu nháp.',
                    'The server needs the mobile API update for safe sending. You can still compose and save drafts.',
                  ),
                ),
              if (d.outcomeUncertain)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.t(
                            'Lần gửi trước chưa xác định. Không gửi lại để tránh trùng thư.',
                            'The previous send is unresolved. Sending again could duplicate it.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: sending
                              ? null
                              : () async {
                                  setState(() => sending = true);
                                  try {
                                    final status = await s.reconcile(d);
                                    if (context.mounted) {
                                      showNotice(context, status);
                                      if (status == 'accepted') {
                                        Navigator.pop(context);
                                      }
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      showNotice(context, e.toString());
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => sending = false);
                                    }
                                  }
                                },
                          child: Text(
                            s.t('Kiểm tra trạng thái', 'Check send status'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              DropdownButtonFormField<int>(
                initialValue: s.addresses.any((a) => a.id == d.accountId)
                    ? d.accountId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('Từ', 'From')),
                items: s.addresses
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.email, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: locked
                    ? null
                    : (v) {
                        d.accountId = v!;
                        changed();
                      },
              ),
              const SizedBox(height: 16),
              for (final field in [
                (to, s.t('Đến', 'To')),
                (cc, 'CC'),
                (bcc, 'BCC'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: field.$1,
                    readOnly: locked,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: field.$2,
                      hintText: 'name@example.com',
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
              TextField(
                controller: subject,
                readOnly: locked,
                decoration: InputDecoration(
                  labelText: s.t('Tiêu đề', 'Subject'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: body,
                readOnly: locked,
                keyboardType: TextInputType.multiline,
                minLines: 10,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: s.t('Viết nội dung thư…', 'Write your email…'),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              if (picking) const LinearProgressIndicator(),
              for (final file in d.attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(asText(file['filename'])),
                  subtitle: Text('${(asInt(file['size']) / 1024).ceil()} KB'),
                  trailing: IconButton(
                    tooltip: s.t('Gỡ tệp', 'Remove file'),
                    onPressed: locked
                        ? null
                        : () {
                            setState(() => d.attachments.remove(file));
                            save();
                          },
                    icon: const Icon(Icons.close),
                  ),
                ),
              Text(
                error.isNotEmpty
                    ? error
                    : saved
                    ? s.t(
                        'Đã lưu nháp mã hóa trên thiết bị',
                        'Draft encrypted and saved on this device',
                      )
                    : s.t('Tự động lưu nháp', 'Draft autosave'),
                style: TextStyle(
                  fontSize: 12,
                  color: error.isEmpty
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: locked || picking || !s.capabilities.safeSend
                    ? null
                    : send,
                icon: const Icon(Icons.send_outlined),
                label: Text(s.t('Gửi thư', 'Send email')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
