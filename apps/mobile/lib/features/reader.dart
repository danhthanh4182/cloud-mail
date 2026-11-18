import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html;

import '../app_controller.dart';
import '../domain/mail.dart';
import '../design_system/components.dart';
import 'compose.dart';

class ReaderScreen extends StatefulWidget {
  final AppController state;
  final MailMessage mail;
  const ReaderScreen({super.key, required this.state, required this.mail});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late MailMessage m;
  bool summarizing = false, downloading = false;
  Map<String, dynamic>? summary;
  AppController get s => widget.state;
  @override
  void initState() {
    super.initState();
    m = widget.mail;
  }

  void reply({bool forward = false}) {
    final draft = MailDraft(
      accountId: m.accountId,
      replyId: m.id,
      sendType: forward ? 'forward' : 'reply',
      to: forward ? '' : m.sender,
      subject: '${forward ? 'Fwd' : 'Re'}: ${m.subject}',
      body: '\n\n—— ${m.displayName} · ${m.time} ——\n${m.body}',
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

  Future<void> download(Map<String, dynamic> file) async {
    final ctx = context;
    setState(() => downloading = true);
    try {
      if (!s.capabilities.organization) {
        throw FormatException(
          s.t(
            'Máy chủ cần API tải tệp có kiểm tra quyền sở hữu.',
            'The server needs the owned attachment API update.',
          ),
        );
      }
      final bytes = await s.api!.attachment(
        asInt(file['attId'] ?? file['att_id']),
      );
      if (!ctx.mounted) return;
      await FilePicker.saveFile(
        dialogTitle: s.t('Lưu tệp đính kèm', 'Save attachment'),
        fileName: asText(file['filename']).replaceAll(RegExp(r'[/\\]'), '_'),
        bytes: bytes,
      );
      if (ctx.mounted) {
        showNotice(
          ctx,
          s.t('Đã hoàn tất hộp thoại lưu tệp', 'Save dialog completed'),
        );
      }
    } catch (e) {
      if (ctx.mounted) showNotice(ctx, e.toString());
    } finally {
      if (ctx.mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final links = html
        .parse(m.content)
        .querySelectorAll('a[href]')
        .map((a) => a.attributes['href']!)
        .where((url) {
          final u = Uri.tryParse(url);
          return u != null && ['https', 'http', 'mailto'].contains(u.scheme);
        })
        .toSet()
        .take(30);
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
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(m.displayName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        m.sender,
                        style: TextStyle(
                          fontSize: 14,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${s.t('Đến', 'To')}: ${m.to}',
                        style: TextStyle(
                          fontSize: 14,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        m.time,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (m.labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  spacing: 8,
                  children: m.labels.map((e) => Chip(label: Text(e))).toList(),
                ),
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
            Text(
              m.body.isEmpty
                  ? s.t('(Thư không có nội dung văn bản)', '(No text content)')
                  : m.body,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (m.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  s.t(
                    'Ảnh từ xa và mã thực thi đã bị chặn. Nội dung được chuyển thành văn bản an toàn.',
                    'Remote images and executable content are blocked. Content is rendered as safe text.',
                  ),
                  style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                ),
              ),
            for (final url in links)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(
                    url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () async {
                    if (await confirm(
                      context,
                      s,
                      s.t('Mở liên kết ngoài?', 'Open external link?'),
                      url,
                    )) {
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
              ),
            if (downloading) const LinearProgressIndicator(),
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
                OutlinedButton.icon(
                  onPressed: () => reply(forward: true),
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
