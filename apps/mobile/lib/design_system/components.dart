import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';

void showNotice(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

Future<T?> action<T>(BuildContext context, Future<T> Function() run) async {
  try {
    return await run();
  } catch (e) {
    if (context.mounted) showNotice(context, e.toString());
    return null;
  }
}

Future<bool> confirm(
  BuildContext context,
  AppController state,
  String title,
  String body, {
  String? label,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(state.t('Hủy', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label ?? state.t('Xác nhận', 'Confirm')),
          ),
        ],
      ),
    ) ??
    false;

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = name.trim().split(RegExp(r'\s+'));
    final initial = name.trim().isEmpty
        ? '?'
        : parts.length > 1
        ? '${parts.first.characters.first}${parts.last.characters.first}'
        : name.characters.first;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.primary,
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * .33),
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final Widget? action;
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class OtpCard extends StatelessWidget {
  final AppController state;
  final String code, sender;
  final bool compact;
  const OtpCard({
    super.key,
    required this.state,
    required this.code,
    required this.sender,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (compact) {
      return Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: c.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                code,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: c.primary,
                ),
              ),
            ),
            IconButton(
              tooltip: state.t(
                'Sao chép mã xác nhận',
                'Copy verification code',
              ),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) {
                  showNotice(context, state.t('Đã sao chép mã', 'Code copied'));
                }
              },
              icon: Icon(Icons.copy_outlined, color: c.primary, size: 20),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_outlined, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$sender · ${state.t('Mã xác nhận', 'Verification code')}',
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              SelectableText(
                code,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3,
                  color: c.onSurface,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    showNotice(
                      context,
                      state.t('Đã sao chép mã', 'Code copied'),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(state.t('Sao chép', 'Copy')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.t(
              'Đối chiếu với nội dung thư trước khi sử dụng.',
              'Check the original email before using the code.',
            ),
            style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class ConnectionBanner extends StatelessWidget {
  final AppController state;
  const ConnectionBanner(this.state, {super.key});
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.t(
                'Chưa đồng bộ được. Đang hiển thị dữ liệu đã lưu.',
                'Sync unavailable. Showing saved data.',
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          IconButton(
            tooltip: state.t('Thử lại', 'Retry'),
            onPressed: () => state.loadMessages(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    ),
  );
}

Map<String, String> mailCategories(AppController state) => {
  'primary': state.t('Chính', 'Primary'),
  'updates': state.t('Cập nhật', 'Updates'),
  'promotions': state.t('Khuyến mãi', 'Promotions'),
  'security': state.t('Bảo mật', 'Security'),
  'invoice': state.t('Hóa đơn', 'Invoice'),
};
