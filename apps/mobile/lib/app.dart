import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'design_system/theme.dart';
import 'features/login.dart';
import 'features/mailbox.dart';

class CloudMailApp extends StatelessWidget {
  final AppController controller;
  const CloudMailApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      key: ValueKey(controller.signedIn ? controller.scope : 'signed-out'),
      title: 'Cloud Mail',
      debugShowCheckedModeBanner: false,
      theme: MailTheme.create(Brightness.light),
      darkTheme: MailTheme.create(Brightness.dark),
      themeMode: controller.theme == 'dark'
          ? ThemeMode.dark
          : controller.theme == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      locale: Locale(controller.language),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: !controller.ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : controller.signedIn
          ? MailboxScreen(state: controller)
          : LoginScreen(state: controller),
    ),
  );
}
