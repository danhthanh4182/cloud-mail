import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_mail/app.dart';
import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';
import 'package:cloud_mail/domain/mail.dart';

import 'session_test.dart' show MemoryVault;

void main() {
  for (final width in [360.0, 412.0, 840.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('login and mailbox fit width $width text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final state = AppController(MemoryVault())..ready = true;
        await tester.pumpWidget(CloudMailApp(controller: state));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        state.api = ApiClient(Uri.parse('https://mail.example.com'));
        state.profile = {'userId': 1, 'email': 'fixture@example.com'};
        state.addresses = [
          const MailAddress(id: 10, email: 'fixture@example.com'),
        ];
        state.messages = [
          const MailMessage(
            id: 100,
            sender: 'security@example.com',
            name: 'Example Security',
            subject: 'Mã xác nhận của bạn',
            text: 'Mã xác nhận của bạn là 083741.',
            time: '2026-11-18 10:20:30',
          ),
        ];
        state.changed();
        await tester.pumpAndSettle();
        expect(find.text('083741'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      });
    }
  }
}
