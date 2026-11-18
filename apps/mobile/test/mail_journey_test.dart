import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_mail/app.dart';
import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';

import 'session_test.dart' show MemoryVault;

void main() {
  testWidgets(
    'native login → read → reply → confirm send keeps stable intent and clears draft',
    (tester) async {
      var sends = 0;
      Map<String, dynamic>? sent;
      final mail = {
        'emailId': 100,
        'accountId': 10,
        'subject': 'Fixture verification',
        'sendEmail': 'controlled@example.com',
        'name': 'Controlled sender',
        'toEmail': 'fixture@example.com',
        'text': 'Your verification code is 482619',
        'unread': 0,
      };
      late AppController state;
      await tester.runAsync(() async {
        state = AppController(
          MemoryVault(),
          apiFactory: (origin, token, language) => ApiClient(
            origin,
            token: token,
            client: MockClient((request) async {
              dynamic data;
              switch (request.url.path) {
                case '/api/login':
                  data = {'token': 'fixture-token'};
                case '/api/my/loginUserInfo':
                  data = {'userId': 1, 'email': 'fixture@example.com'};
                case '/api/account/list':
                  data = [
                    {'accountId': 10, 'email': 'fixture@example.com'},
                  ];
                case '/api/mobile/capabilities':
                  data = {'organization': true, 'safeSend': true};
                case '/api/mobile/mail':
                  data = {
                    'list': [mail],
                    'hasMore': false,
                  };
                case '/api/mobile/mail/100':
                  data = {...mail, 'attList': []};
                case '/api/email/read':
                  data = null;
                case '/api/mobile/send':
                  sends++;
                  expect(request.headers['Idempotency-Key'], isNotEmpty);
                  sent = jsonDecode(request.body);
                  data = {'state': 'accepted'};
                default:
                  throw StateError(
                    'Unexpected fixture route ${request.url.path}',
                  );
              }
              return http.Response(
                jsonEncode({'code': 200, 'data': data}),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        )..ready = true;
      });
      await tester.pumpWidget(CloudMailApp(controller: state));
      await tester.enterText(
        find.byKey(const Key('server')),
        'https://mail.example.com',
      );
      await tester.enterText(
        find.byKey(const Key('email')),
        'fixture@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('password')),
        'fixture-password',
      );
      await tester.ensureVisible(find.byKey(const Key('sign-in')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('sign-in')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(state.signedIn, true);
      expect(find.text('Fixture verification'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Fixture verification'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(state.messages.single.unread, false);
      expect(find.text('482619'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Trả lời'));
      await tester.tap(find.widgetWithText(FilledButton, 'Trả lời'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.byTooltip('Gửi thư')));
      await tester.pumpAndSettle();
      expect(find.text('Gửi thư này?'), findsOneWidget);
      expect(sends, 0);
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Gửi'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(sends, 1);
      expect(sent!['receiveEmail'], ['controlled@example.com']);
      expect(sent!['sendType'], 'reply');
      expect(sent!['emailId'], 100);
      expect(state.drafts, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
