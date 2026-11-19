import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';
import 'package:cloud_mail/domain/mail.dart';

import 'session_test.dart' show MemoryVault;

void main() {
  test(
    'missing intent permits only explicit replay with the same key and content',
    () async {
      final keys = <String>[];
      final app = AppController(MemoryVault())
        ..profile = {'userId': 1}
        ..capabilities = const Capabilities(safeSend: true)
        ..api = ApiClient(
          Uri.parse('https://mail.example.com'),
          client: MockClient((r) async {
            if (r.method == 'GET') {
              return http.Response(
                '{"code":404,"message":"Send intent not found"}',
                200,
              );
            }
            keys.add(r.headers['Idempotency-Key']!);
            return http.Response(
              '{"code":200,"data":{"state":"accepted"}}',
              200,
            );
          }),
        );
      final d = MailDraft(
        accountId: 10,
        to: 'controlled@example.com',
        body: 'fixture',
        requestKey: 'immutable-request-123',
        sendState: 'pending',
      );
      await app.reconcile(d);
      expect(d.sendState, 'notSubmitted');
      expect(d.outcomeUncertain, true);
      expect(await app.retryMissingIntent(d), 'accepted');
      expect(keys, ['immutable-request-123']);
      app.dispose();
    },
  );
}
