import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../domain/mail.dart';

class LoginScreen extends StatefulWidget {
  final AppController state;
  const LoginScreen({super.key, required this.state});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController();
  bool _visible = false;
  String _error = '';
  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = '');
    try {
      await widget.state.login(_server.text, _email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state, c = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(Icons.mail_outline, color: c.onPrimary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Cloud Mail',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: s.t('Ngôn ngữ', 'Language'),
                          onPressed: () => s.updatePreferences(
                            language: s.language == 'vi' ? 'en' : 'vi',
                          ),
                          icon: const Icon(Icons.language),
                        ),
                      ],
                    ),
                    const SizedBox(height: 46),
                    Text(
                      s.t(
                        'Hộp thư,\ntheo nhịp của bạn.',
                        'Your inbox.\nYour own pace.',
                      ),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      s.t(
                        'Kết nối máy chủ Cloud Mail của bạn. Đọc, soạn và xử lý email trong một không gian riêng.',
                        'Connect your Cloud Mail server. Read, write and organize email in your own space.',
                      ),
                      style: TextStyle(color: c.onSurfaceVariant, height: 1.6),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      key: const Key('server'),
                      controller: _server,
                      enabled: !s.busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: s.t('Máy chủ webmail', 'Webmail server'),
                        hintText: 'https://mail.example.com',
                        prefixIcon: const Icon(Icons.dns_outlined),
                      ),
                      validator: (v) {
                        try {
                          validateServer(v ?? '');
                          return null;
                        } catch (_) {
                          return s.t(
                            'Nhập địa chỉ HTTPS hợp lệ.',
                            'Enter a valid HTTPS origin.',
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      key: const Key('email'),
                      controller: _email,
                      enabled: !s.busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: s.t('Địa chỉ email', 'Email address'),
                        prefixIcon: const Icon(Icons.alternate_email),
                      ),
                      validator: (v) {
                        try {
                          return parseRecipients(v ?? '').length == 1
                              ? null
                              : s.t('Nhập email của bạn.', 'Enter your email.');
                        } catch (_) {
                          return s.t('Email không hợp lệ.', 'Invalid email.');
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      key: const Key('password'),
                      controller: _password,
                      enabled: !s.busy,
                      obscureText: !_visible,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: s.t('Mật khẩu', 'Password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: s.t(
                            'Hiện hoặc ẩn mật khẩu',
                            'Show or hide password',
                          ),
                          onPressed: () => setState(() => _visible = !_visible),
                          icon: Icon(
                            _visible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (v) => (v ?? '').isEmpty
                          ? s.t('Nhập mật khẩu.', 'Enter your password.')
                          : null,
                      onFieldSubmitted: (_) => _login(),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Semantics(
                        liveRegion: true,
                        child: Text(_error, style: TextStyle(color: c.error)),
                      ),
                    ],
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('sign-in'),
                        onPressed: s.busy ? null : _login,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: s.busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(s.t('Mở hộp thư', 'Open inbox')),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                          color: c.onSurfaceVariant,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            s.t(
                              'Phiên đăng nhập được lưu trong bộ nhớ bảo mật của thiết bị. App cần máy chủ Cloud Mail đang hoạt động.',
                              'Your session uses secure device storage. A running Cloud Mail server is required.',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
