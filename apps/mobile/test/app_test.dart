import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_mail/app.dart';
import 'package:cloud_mail/app_controller.dart';

import 'session_test.dart' show MemoryVault;

void main() {
  testWidgets(
    'native login exposes server, email, password and sign-in controls',
    (tester) async {
      final state = AppController(MemoryVault())..ready = true;
      await tester.pumpWidget(CloudMailApp(controller: state));
      expect(find.text('Cloud Mail'), findsOneWidget);
      expect(find.byKey(const Key('server')), findsOneWidget);
      expect(find.byKey(const Key('email')), findsOneWidget);
      expect(find.byKey(const Key('password')), findsOneWidget);
      expect(find.byKey(const Key('sign-in')), findsOneWidget);
      state.dispose();
    },
  );
}
