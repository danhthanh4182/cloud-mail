import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../domain/mail.dart';
import '../design_system/components.dart';

class SettingsScreen extends StatelessWidget {
  final AppController state;
  const SettingsScreen({super.key, required this.state});

  Future<String?> prompt(
    BuildContext context,
    String title, {
    String value = '',
    bool obscure = false,
  }) async {
    final controller = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscure,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(state.t('Hủy', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(state.t('Lưu', 'Save')),
          ),
        ],
      ),
    );
    // The route may still be animating out; dispose after the transition.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return result;
  }

  Future<void> manage(
    BuildContext context,
    MailAddress address,
    String value,
  ) async {
    final s = state;
    if (value == 'name') {
      final name = await prompt(
        context,
        s.t('Tên hiển thị', 'Display name'),
        value: address.name,
      );
      if (name == null || !context.mounted) return;
      await action(context, () async {
        await s.api!.request(
          'PUT',
          '/account/setName',
          body: {'accountId': address.id, 'name': name},
        );
        await s.refreshAddresses();
      });
    } else {
      final approved = await confirm(
        context,
        s,
        s.t('Xóa địa chỉ này?', 'Delete this address?'),
        s.t(
          'Thư thuộc địa chỉ có thể bị xóa vĩnh viễn theo chính sách máy chủ. Hành động này không có hoàn tác.',
          'Mail for this address may be permanently deleted under the server policy. This cannot be undone.',
        ),
      );
      if (!approved || !context.mounted) return;
      await action(context, () async {
        await s.api!.request(
          'DELETE',
          '/account/delete',
          query: {'accountId': '${address.id}'},
        );
        if (s.selectedAddress == address.id) s.selectedAddress = null;
        await s.refreshAddresses();
        await s.loadMessages();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Avatar(
                  '${s.profile['name'] ?? s.profile['email'] ?? ''}',
                  size: 54,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${s.profile['name'] ?? ''}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('${s.profile['email'] ?? ''}'),
                      const SizedBox(height: 8),
                      Text(
                        s.api!.origin.host,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          s.t('Giao diện & ngôn ngữ', 'Appearance & language'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: s.theme,
          decoration: InputDecoration(labelText: s.t('Giao diện', 'Theme')),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(s.t('Theo hệ thống', 'System')),
            ),
            DropdownMenuItem(value: 'light', child: Text(s.t('Sáng', 'Light'))),
            DropdownMenuItem(value: 'dark', child: Text(s.t('Tối', 'Dark'))),
          ],
          onChanged: (value) => s.updatePreferences(theme: value),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: s.language,
          decoration: const InputDecoration(labelText: 'Ngôn ngữ / Language'),
          items: const [
            DropdownMenuItem(value: 'vi', child: Text('Tiếng Việt')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (value) => s.updatePreferences(language: value),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                s.t('Địa chỉ email', 'Email addresses'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: s.t('Thêm địa chỉ', 'Add address'),
              icon: const Icon(Icons.add),
              onPressed: () async {
                final email = await prompt(
                  context,
                  s.t('Địa chỉ email mới', 'New email address'),
                );
                if (email == null || !context.mounted) return;
                await action(context, () async {
                  if (parseRecipients(email).length != 1) {
                    throw const FormatException('Enter one email address');
                  }
                  await s.api!.request(
                    'POST',
                    '/account/add',
                    body: {'email': email.trim(), 'token': ''},
                  );
                  await s.refreshAddresses();
                });
              },
            ),
          ],
        ),
        for (final a in s.addresses)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(a.name.isEmpty ? a.email : a.name),
            subtitle: a.name.isEmpty ? null : Text(a.email),
            trailing: PopupMenuButton<String>(
              tooltip: s.t('Quản lý địa chỉ', 'Manage address'),
              onSelected: (value) => manage(context, a, value),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'name',
                  child: Text(s.t('Đổi tên', 'Rename')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(s.t('Xóa địa chỉ', 'Delete address')),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text(
          s.t('Bảo mật & thông báo', 'Security & notifications'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: Text(s.t('Đổi mật khẩu', 'Change password')),
          onTap: () async {
            final password = await prompt(
              context,
              s.t('Mật khẩu mới', 'New password'),
              obscure: true,
            );
            if (password == null || password.length < 6 || !context.mounted) {
              return;
            }
            await action(context, () async {
              await s.api!.request(
                'PUT',
                '/my/resetPassword',
                body: {'password': password},
              );
              if (context.mounted) {
                showNotice(
                  context,
                  s.t(
                    'Đã cập nhật mật khẩu. Các phiên khác tùy chính sách máy chủ.',
                    'Password updated. Other sessions follow the server policy.',
                  ),
                );
              }
            });
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(
            s.t(
              'Thông báo đẩy chưa cấu hình',
              'Push notifications not configured',
            ),
          ),
          subtitle: Text(
            s.t(
              'Hộp thư tự làm mới khi ứng dụng đang mở. Cần cấu hình FCM để nhận khi đóng app.',
              'Mail refreshes while the app is open. FCM configuration is required for delivery while closed.',
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(
            s.t('Dữ liệu mã hóa trên thiết bị', 'Encrypted device data'),
          ),
          subtitle: Text(
            s.t(
              'Phiên, cache và nháp được phân vùng theo máy chủ và người dùng.',
              'Sessions, cache and drafts are isolated by server and user.',
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            final approved = await confirm(
              context,
              s,
              s.t('Đăng xuất?', 'Sign out?'),
              s.t(
                'Bản nháp mã hóa được giữ và khôi phục khi đăng nhập cùng tài khoản.',
                'Encrypted drafts remain and restore when you sign in to the same account.',
              ),
            );
            if (approved && context.mounted) await action(context, s.logout);
          },
          icon: const Icon(Icons.logout),
          label: Text(s.t('Đăng xuất', 'Sign out')),
        ),
        const SizedBox(height: 24),
        Text(
          'Cloud Mail Native · 0.2.0\n${s.t('Bản kiểm thử · chức năng mới cần Worker tương thích', 'Test build · new features require a compatible Worker')}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
