import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/api.dart';
import 'android_mail_body.dart';
import 'mail_html_document.dart';
import 'rich_mail.dart';

import '../app_controller.dart';
import '../domain/mail.dart';
import '../design_system/components.dart';
import 'compose.dart';
import 'message_header.dart';

class ReaderScreen extends StatefulWidget {
  final AppController state;
  final MailMessage mail;
  const ReaderScreen({super.key, required this.state, required this.mail});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late MailMessage m;
  late final MailHtmlDocument? document;
  late final Future<({List<MailMessage> list, bool truncated})>? thread;
  bool showImages = false;
  Completer<void>? transfer;
  double? transferProgress;
  bool summarizing = false, downloading = false;
  Map<String, dynamic>? summary;
  AppController get s => widget.state;
  @override
  void initState() {
    super.initState();
    m = widget.mail;
    document = MailHtmlDocument.parse(m.content);
    thread = s.capabilities.conversation && !s.offline
        ? s.conversation(m)
        : null;
  }

  @override
  void dispose() {
    cancelTransfer();
    super.dispose();
  }

  void cancelTransfer() {
    if (transfer?.isCompleted == false) transfer!.complete();
  }

  void reply({
    bool forward = false,
    String suggestion = '',
    List<Map<String, dynamic>>? attachments,
  }) {
    final draft = MailDraft(
      accountId: m.accountId,
      replyId: m.id,
      sendType: forward ? 'forward' : 'reply',
      to: forward
          ? ''
          : m.type == 1
          ? m.to
          : m.sender,
      subject: '${forward ? 'Fwd' : 'Re'}: ${m.subject}',
      body: '$suggestion\n\n—— ${m.displayName} · ${m.time} ——\n${m.body}',
      attachments: attachments,
    );
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ComposeScreen(state: s, draft: draft),
      ),
    );
  }

  Future<void> organize(String target) async {
    final ctx = context;
    final next = await action(ctx, () => s.organize(m, target: target));
    if (next != null && ctx.mounted) {
      setState(() => m = next);
      showNotice(ctx, s.t('Đã cập nhật thư', 'Message updated'));
      await s.loadMessages();
      if (ctx.mounted) Navigator.pop(ctx);
    }
  }

  Future<void> label() async {
    final ctx = context;
    final controller = TextEditingController(text: m.labels.join(', '));
    final value = await showDialog<String>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('Nhãn thư', 'Labels')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.t('Công việc, Cá nhân', 'Work, Personal'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.t('Hủy', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(s.t('Lưu', 'Save')),
          ),
        ],
      ),
    );
    if (value != null && ctx.mounted) {
      final next = await action(
        ctx,
        () => s.organize(
          m,
          labels: value
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList(),
        ),
      );
      if (next != null && ctx.mounted) setState(() => m = next);
    } /* Dialog route owns the controller until its reverse animation finishes. */
  }

  Future<Uint8List> fetchFile(Map<String, dynamic> file) async {
    if (!s.capabilities.organization) {
      throw ApiFailure(
        503,
        s.t(
          'Máy chủ cần API tải tệp mới.',
          'Update the server to download attachments.',
        ),
      );
    }
    final current = transfer!;
    final bytes = await s.api!.attachment(
      asInt(file['attId'] ?? file['att_id']),
      abort: current.future,
      progress: (received, total) {
        if (mounted && current == transfer) {
          setState(
            () => transferProgress = total == null || total == 0
                ? null
                : received / total,
          );
        }
      },
    );
    if (current.isCompleted) throw const ApiFailure(499, 'Download canceled');
    return bytes;
  }

  Future<void> runTransfer(Future<void> Function() load) async {
    if (downloading) return;
    setState(() {
      transfer = Completer<void>();
      downloading = true;
      transferProgress = null;
    });
    try {
      await load();
    } on ApiFailure catch (e) {
      if (e.code != 499 && mounted) showNotice(context, e.message);
    } catch (e) {
      if (mounted) showNotice(context, e.toString());
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> download(Map<String, dynamic> file) => runTransfer(() async {
    final bytes = await fetchFile(file);
    if (!mounted) return;
    final destination = await FilePicker.saveFile(
      dialogTitle: s.t('Lưu tệp đính kèm', 'Save attachment'),
      fileName: asText(file['filename']).replaceAll(RegExp(r'[/\\]'), '_'),
      bytes: bytes,
    );
    if (destination != null && mounted) {
      showNotice(context, s.t('Đã lưu tệp', 'File saved'));
    }
  });

  Future<void> forward() async {
    if (m.attachments.isEmpty || !s.capabilities.organization) {
      reply(forward: true);
      return;
    }
    final checked = <int>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            s.t('Chọn tệp để chuyển tiếp', 'Select original attachments'),
          ),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (index, file) in m.attachments.indexed)
                  CheckboxListTile(
                    value: checked.contains(index),
                    title: Text(asText(file['filename'])),
                    onChanged: asInt(file['size']) > 5 * 1024 * 1024
                        ? null
                        : (value) => update(() {
                            if (value == true) {
                              checked.add(index);
                            } else {
                              checked.remove(index);
                            }
                          }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('Hủy', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('Tiếp tục', 'Continue')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    await runTransfer(() async {
      final attachments = <Map<String, dynamic>>[];
      var total = 0;
      if (checked.length > 10) {
        throw const FormatException('Maximum 10 attachments');
      }
      for (final index in checked) {
        final file = m.attachments[index];
        final data = await fetchFile(file);
        total += data.length;
        if (data.length > 5 * 1024 * 1024 || total > 10 * 1024 * 1024) {
          throw const FormatException('Maximum 5 MB per file and 10 MB total');
        }
        attachments.add({
          'filename': asText(file['filename']),
          'mimeType': asText(file['contentType']).isEmpty
              ? 'application/octet-stream'
              : file['contentType'],
          'size': data.length,
          'content': base64Encode(data),
        });
      }
      if (mounted) reply(forward: true, attachments: attachments);
    });
  }

  Future<void> suggestReply() async {
    if (!await confirm(
      context,
      s,
      s.t('Tạo gợi ý trả lời?', 'Generate a reply suggestion?'),
      s.t(
        'Gửi nội dung đã rút gọn và che dữ liệu nhạy cảm tới Workers AI.',
        'Send a shortened, redacted excerpt to Workers AI.',
      ),
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => summarizing = true);
    final draft = await action(context, () => s.suggestReply(m));
    if (!mounted) return;
    setState(() => summarizing = false);
    if (draft != null) reply(suggestion: draft);
  }

  Future<void> chooseCategory() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
          s.t(
            'Phân loại thư từ người gửi này',
            'Categorize mail from this sender',
          ),
        ),
        children: [
          for (final entry in mailCategories(s).entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, entry.key),
              child: Text(entry.value),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(s.t('Xóa quy tắc', 'Remove rule')),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      final saved = await action(context, () async {
        await s.setSenderCategory(m.sender, selected);
        return true;
      });
      if (mounted && saved == true) {
        showNotice(context, s.t('Đã cập nhật quy tắc', 'Sender rule updated'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final html = document;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: m.starred
                ? s.t('Bỏ sao', 'Remove star')
                : s.t('Gắn sao', 'Star'),
            onPressed: () async {
              final ok = await action(context, () async {
                await s.toggleStar(m);
                return true;
              });
              if (ok == true && context.mounted) {
                setState(() => m = m.copy(starred: !m.starred));
              }
            },
            icon: Icon(m.starred ? Icons.star : Icons.star_border),
          ),
          if (s.capabilities.organization)
            PopupMenuButton<String>(
              tooltip: s.t('Thao tác thư', 'Message actions'),
              onSelected: (value) {
                if (value == 'labels') {
                  label();
                } else if (value == 'unread') {
                  action(context, () async {
                    m = await s.organize(m, read: false);
                    if (context.mounted) Navigator.pop(context);
                  });
                } else {
                  organize(value);
                }
              },
              itemBuilder: (_) => [
                for (final entry in {
                  'archive': s.t('Lưu trữ', 'Archive'),
                  'spam': s.t('Chuyển vào Spam', 'Move to Spam'),
                  'trash': s.t('Chuyển vào Thùng rác', 'Move to Trash'),
                  'inbox': s.t('Khôi phục vào Hộp thư', 'Restore to Inbox'),
                  'labels': s.t('Sửa nhãn', 'Edit labels'),
                  'unread': s.t('Đánh dấu chưa đọc', 'Mark unread'),
                }.entries)
                  PopupMenuItem(value: entry.key, child: Text(entry.value)),
              ],
            ),
        ],
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              m.subject.isEmpty
                  ? s.t('(Không tiêu đề)', '(No subject)')
                  : m.subject,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (m.labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: MessageLabels(
                  m.labels,
                  moreLabel: (count) =>
                      s.t('$count nhãn khác', '$count more labels'),
                ),
              ),
            const SizedBox(height: 24),
            MessageHeader(state: s, mail: m),
            if (thread != null)
              FutureBuilder<({List<MailMessage> list, bool truncated})>(
                future: thread,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      s.t(
                        'Không tải được hội thoại.',
                        'Conversation could not be loaded.',
                      ),
                    );
                  }
                  final related = snapshot.data?.list ?? [];
                  return related.isEmpty
                      ? const SizedBox.shrink()
                      : ExpansionTile(
                          title: Text(
                            s.t(
                              'Hội thoại · ${related.length + 1} thư',
                              'Conversation · ${related.length + 1} messages',
                            ),
                          ),
                          children: [
                            for (final item
                                in ([...related, m]..sort((a, b) {
                                  final byTime = a.time.compareTo(b.time);
                                  return byTime == 0
                                      ? a.id.compareTo(b.id)
                                      : byTime;
                                })))
                              _ConversationItem(
                                key: ValueKey(item.id),
                                state: s,
                                message: item,
                                current: item.id == m.id,
                              ),
                            if (snapshot.data?.truncated == true)
                              Text(
                                s.t(
                                  'Hội thoại còn thư ngoài giới hạn hiển thị.',
                                  'Older conversation results are limited.',
                                ),
                              ),
                          ],
                        );
                },
              ),
            if (s.capabilities.smartMail && m.category.isNotEmpty)
              Text(
                s.t(
                  '${mailCategories(s)[m.category]} · ${m.reason == 'senderRule'
                      ? 'Theo quy tắc người gửi'
                      : m.reason == 'subject'
                      ? 'Theo tiêu đề'
                      : 'Mặc định'}',
                  '${mailCategories(s)[m.category]} · ${m.reason == 'senderRule'
                      ? 'Sender rule'
                      : m.reason == 'subject'
                      ? 'Based on subject'
                      : 'Default'}',
                ),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            if (s.capabilities.smartMail && m.sender.contains('@'))
              TextButton.icon(
                onPressed: chooseCategory,
                icon: const Icon(Icons.label_outline),
                label: Text(s.t('Phân loại theo người gửi', 'Sender category')),
              ),
            if (m.code.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: OtpCard(state: s, code: m.code, sender: m.displayName),
              ),
            const SizedBox(height: 24),
            if (s.capabilities.assistant)
              OutlinedButton.icon(
                onPressed: summarizing
                    ? null
                    : () async {
                        if (!await confirm(
                          context,
                          s,
                          s.t('Tóm tắt bằng AI?', 'Summarize with AI?'),
                          s.t(
                            'Nội dung được rút gọn và che mã, liên kết trước khi gửi tới Workers AI. Luôn đối chiếu với thư gốc.',
                            'A shortened email with codes and links redacted will be sent to Workers AI. Always check the original.',
                          ),
                        )) {
                          return;
                        }
                        if (!context.mounted) return;
                        setState(() => summarizing = true);
                        final result = await action(
                          context,
                          () => s.summarize(m),
                        );
                        if (context.mounted) {
                          setState(() {
                            summary = result;
                            summarizing = false;
                          });
                        }
                      },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  summarizing
                      ? s.t('Đang tóm tắt…', 'Summarizing…')
                      : s.t('Tóm tắt thư bằng AI', 'Summarize with AI'),
                ),
              ),
            if (summary != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.t(
                          'Tóm tắt do AI tạo · hãy kiểm tra',
                          'AI summary · verify before use',
                        ),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(asText(summary!['summary'])),
                      for (final quote in decodeList(summary!['evidence']))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '“$quote”',
                            style: TextStyle(
                              color: c.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (html != null && html.remoteImages.isNotEmpty && !showImages)
              OutlinedButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  s.t(
                    'Tải ảnh HTTPS trong thư này',
                    'Load HTTPS images for this message',
                  ),
                ),
                onPressed: () async {
                  if (await confirm(
                        context,
                        s,
                        s.t('Tải ảnh bên ngoài?', 'Load external images?'),
                        s.t(
                          'Máy chủ ảnh có thể biết bạn đã mở thư.',
                          'Image hosts may learn that you opened the message.',
                        ),
                      ) &&
                      mounted) {
                    setState(() => showImages = true);
                  }
                },
              ),
            _MessageBody(
              state: s,
              message: m,
              document: html,
              showImages: showImages,
            ),
            if (downloading) ...[
              LinearProgressIndicator(value: transferProgress),
              TextButton(
                onPressed: cancelTransfer,
                child: Text(s.t('Hủy tải tệp', 'Cancel transfer')),
              ),
            ],
            for (final file in m.attachments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(asText(file['filename'])),
                subtitle: Text('${(asInt(file['size']) / 1024).ceil()} KB'),
                trailing: IconButton(
                  tooltip: s.t('Lưu tệp', 'Save file'),
                  onPressed: downloading ? null : () => download(file),
                  icon: const Icon(Icons.download_outlined),
                ),
              ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => reply(),
                  icon: const Icon(Icons.reply),
                  label: Text(s.t('Trả lời', 'Reply')),
                ),
                if (s.capabilities.assistant)
                  OutlinedButton.icon(
                    onPressed: summarizing ? null : suggestReply,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(s.t('Gợi ý trả lời', 'Suggest reply')),
                  ),
                OutlinedButton.icon(
                  onPressed: downloading ? null : forward,
                  icon: const Icon(Icons.forward),
                  label: Text(s.t('Chuyển tiếp', 'Forward')),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ConversationItem extends StatefulWidget {
  final AppController state;
  final MailMessage message;
  final bool current;
  const _ConversationItem({
    super.key,
    required this.state,
    required this.message,
    required this.current,
  });
  @override
  State<_ConversationItem> createState() => _ConversationItemState();
}

class _ConversationItemState extends State<_ConversationItem> {
  Future<({MailMessage message, MailHtmlDocument? document})>? mail;

  Future<({MailMessage message, MailHtmlDocument? document})> load() async {
    final message = await widget.state.open(widget.message);
    return (
      message: message,
      document: MailHtmlDocument.parse(message.content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final item = widget.message;
    if (widget.current) {
      return ListTile(
        selected: true,
        leading: Avatar(item.displayName, size: 32),
        title: Text(item.displayName),
        subtitle: Text(
          s.t('Thư đang đọc · ${item.time}', 'Current message · ${item.time}'),
        ),
      );
    }
    return ExpansionTile(
      leading: Avatar(item.displayName, size: 32),
      title: Text(item.displayName),
      subtitle: Text('${item.subject} · ${item.time}'),
      onExpansionChanged: (open) {
        if (open && mail == null) setState(() => mail = load());
      },
      children: [
        if (mail != null)
          FutureBuilder<({MailMessage message, MailHtmlDocument? document})>(
            future: mail,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(() => mail = load()),
                  child: Text(s.t('Tải lại thư', 'Retry loading message')),
                );
              }
              final data = snapshot.data;
              if (data == null) return const LinearProgressIndicator();
              final loaded = data.message;
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MessageBody(
                      state: s,
                      message: loaded,
                      document: data.document,
                    ),
                    if (loaded.code.isNotEmpty)
                      OtpCard(
                        state: s,
                        code: loaded.code,
                        sender: loaded.displayName,
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => ReaderScreen(state: s, mail: loaded),
                        ),
                      ),
                      child: Text(
                        s.t(
                          'Mở thư và tệp đính kèm',
                          'Open message and attachments',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MessageBody extends StatelessWidget {
  final AppController state;
  final MailMessage message;
  final MailHtmlDocument? document;
  final bool showImages;

  const _MessageBody({
    required this.state,
    required this.message,
    required this.document,
    this.showImages = false,
  });

  Future<void> _openLink(BuildContext context, Uri url) async {
    if (await confirm(
      context,
      state,
      state.t('Mở liên kết ngoài?', 'Open external link?'),
      '$url',
    )) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final html = document;
    final text = Text(
      message.body.isEmpty
          ? state.t('(Thư không có nội dung văn bản)', '(No text content)')
          : message.body,
      style: Theme.of(context).textTheme.bodyLarge,
    );
    if (html == null) return text;
    return MailBody(
      document: html,
      showImages: showImages,
      onLink: (url) => _openLink(context, url),
      fallback: Builder(
        builder: (context) {
          final fallback = safeMailHtml(message.content);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fallback != null && fallback.nodes.isNotEmpty)
                RichMailBody(document: fallback, showImages: showImages)
              else
                text,
              for (final url in html.links.take(30))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(
                      '$url',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _openLink(context, url),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
