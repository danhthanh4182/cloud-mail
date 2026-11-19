import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';

import 'session_test.dart' show MemoryVault;

void main() {
  test(
    'restored identity is verified before fetching or caching network mail',
    () async {
      final vault = MemoryVault();
      await vault.write(
        'session',
        jsonEncode({
          'origin': 'https://mail.example.com',
          'token': 'fixture',
          'profile': {'userId': 1},
          'addresses': [
            {'accountId': 10, 'email': 'a@example.com'},
          ],
        }),
      );
      var mailRequests = 0;
      final app = AppController(
        vault,
        apiFactory: (origin, token, language) => ApiClient(
          origin,
          token: token,
          client: MockClient((r) async {
            if (r.url.path.contains('/email/list') ||
                r.url.path.contains('/mobile/mail')) {
              mailRequests++;
            }
            return http.Response('{"code":200,"data":{"userId":2}}', 200);
          }),
        ),
      );
      await app.initialize();
      expect(mailRequests, 0);
      expect(app.signedIn, false);
      expect(app.ready, true);
      expect(vault.data.keys.where((key) => key.startsWith('mail:')), isEmpty);
      app.dispose();
    },
  );
  test(
    'legacy folders cannot pretend to support server organization',
    () async {
      final app = AppController(MemoryVault());
      await expectLater(app.selectFolder('trash'), throwsA(isA<ApiFailure>()));
      expect(app.folder, 'inbox');
      app.dispose();
    },
  );
}
