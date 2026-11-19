import 'package:cloud_mail/app.dart';
import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';
import 'package:cloud_mail/design_system/components.dart';
import 'package:cloud_mail/domain/mail.dart';
import 'package:cloud_mail/features/reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'session_test.dart' show MemoryVault;

const sample = {
  'emailId': 1,
  'name': 'Delivery team',
  'sendEmail': 'orders@example.test',
  'subject': 'Your receipt',
  'recipient': [
    {'address': 'ana@example.test', 'name': 'Ana Nguyen'},
    {'address': 'operations@example.test'},
  ],
  'cc': '[{"address":"support@example.test","name":"Support Team"}]',
  'labels': ['Purchases', 'Work', 'Needs review'],
  'text': 'A receipt is available.',
};

void main() {
  test('recipient names and boolean DMARC evidence round-trip to cache', () {
    final mail = MailMessage.fromJson({
      ...sample,
      'senderDomainAuthenticated': true,
    });
    final cached = MailMessage.fromJson(mail.copy(unread: false).toJson());
    expect(cached.to, 'ana@example.test, operations@example.test');
    expect(cached.cc, 'support@example.test');
    expect(cached.toPeople.first.name, 'Ana Nguyen');
    expect(cached.ccPeople.single.name, 'Support Team');
    expect(cached.authenticatedDomain, 'example.test');
    expect(
      MailMessage.fromJson({'toEmail': 'old@example.test'})
          .toPeople
          .single
          .displayName,
      'old@example.test',
    );
    for (final signal in [null, false, 1, 'true', 'pass']) {
      expect(
        MailMessage.fromJson({...sample, 'senderDomainAuthenticated': signal})
            .authenticatedDomain,
        isNull,
      );
    }
  });

  testWidgets('reader shows avatars, To and Cc, labels, and DMARC details', (
    tester,
  ) async {
    final state = AppController(MemoryVault())..language = 'en';
    addTearDown(state.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 950);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Future<void> open(Map<String, Object?> data) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ReaderScreen(
          key: ValueKey(data['emailId']),
          state: state,
          mail: MailMessage.fromJson(data),
        ),
      ),
    );

    await open({...sample, 'senderDomainAuthenticated': true});
    expect(find.text('orders@example.test'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    expect(find.byType(Avatar), findsNWidgets(2));
    expect(find.text('ana@example.test'), findsNothing);
    await tester.tap(find.text('To · Ana Nguyen +2'));
    await tester.pumpAndSettle();
    expect(find.text('ana@example.test'), findsOneWidget);
    expect(find.text('operations@example.test'), findsOneWidget);
    expect(find.text('Support Team'), findsOneWidget);
    expect(find.text('support@example.test'), findsOneWidget);
    await tester.tap(find.text('Authenticated domain'));
    await tester.pumpAndSettle();
    expect(find.textContaining('example.test with DMARC'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await open({
      ...sample,
      'emailId': 2,
      'name': 'Example verified sender',
      'text': 'Authentication-Results: mx.cloudflare.net; dmarc=pass',
    });
    expect(find.text('Authenticated domain'), findsNothing);
    expect(find.text('orders@example.test'), findsOneWidget);
  });

  testWidgets(
    'mailbox limits the label preview and shows the verified domain',
    (tester) async {
      final state = AppController(MemoryVault())
        ..ready = true
        ..language = 'en'
        ..api = ApiClient(Uri.parse('https://mail.example.test'))
        ..profile = {'userId': 1}
        ..messages = [
          MailMessage.fromJson({...sample, 'senderDomainAuthenticated': true}),
        ];
      addTearDown(state.dispose);
      await tester.pumpWidget(CloudMailApp(controller: state));
      await tester.pumpAndSettle();
      expect(find.text('Purchases'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('Needs review'), findsNothing);
      expect(
        find.byTooltip('Authenticated domain · example.test'),
        findsOneWidget,
      );
    },
  );
}
