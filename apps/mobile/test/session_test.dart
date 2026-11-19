import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';
import 'package:cloud_mail/data/vault.dart';

class MemoryVault implements Vault {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

http.Response response(String data) =>
    http.Response('{"code":200,"data":$data}', 200);
void main() {
  test(
    'login establishes identity and logout removes only active session',
    () async {
      final vault = MemoryVault();
      final app = AppController(
        vault,
        apiFactory: (uri, token, lang) => ApiClient(
          uri,
          token: token,
          client: MockClient((r) async {
            switch (r.url.path) {
              case '/api/login':
                return response('{"token":"fixture"}');
              case '/api/my/loginUserInfo':
                return response('{"userId":1,"email":"a@example.com"}');
              case '/api/account/list':
                return response('[{"accountId":10,"email":"a@example.com"}]');
              default:
                return response('{}');
            }
          }),
        ),
      );
      await app.login(
        'https://mail.example.com',
        'a@example.com',
        'fixture-password',
      );
      expect(app.signedIn, true);
      expect(
        vault.data.values.any((x) => x.contains('fixture-password')),
        false,
      );
      await app.logout();
      expect(app.signedIn, false);
      expect(await vault.read('session'), null);
    },
  );
  test('logout while login is pending rejects the late session', () async {
    final delayed = Completer<http.Response>();
    final vault = MemoryVault();
    final app = AppController(
      vault,
      apiFactory: (uri, token, lang) => ApiClient(
        uri,
        token: token,
        client: MockClient(
          (r) async =>
              r.url.path == '/api/login' ? delayed.future : response('{}'),
        ),
      ),
    );
    final login = app.login(
      'https://mail.example.com',
      'a@example.com',
      'fixture-password',
    );
    await Future<void>.delayed(Duration.zero);
    await app.logout();
    delayed.complete(response('{"token":"fixture"}'));
    await login;
    expect(app.signedIn, false);
    expect(await vault.read('session'), null);
  });
}
