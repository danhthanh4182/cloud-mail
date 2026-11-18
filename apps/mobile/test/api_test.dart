import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_mail/data/api.dart';

void main() {
  test('legacy token is raw and success envelope is unwrapped', () async {
    final api = ApiClient(
      Uri.parse('https://mail.example.com'),
      token: 'fixture-token',
      client: MockClient((r) async {
        expect(r.headers['Authorization'], 'fixture-token');
        expect(r.followRedirects, false);
        return http.Response('{"code":200,"data":{"emailId":42}}', 200);
      }),
    );
    expect(await api.request('GET', '/email/list'), {'emailId': 42});
  });
  test('HTTP 200 application denial is not a success', () async {
    final api = ApiClient(
      Uri.parse('https://mail.example.com'),
      client: MockClient(
        (_) async => http.Response('{"code":403,"message":"Denied"}', 200),
      ),
    );
    await expectLater(
      api.request('GET', '/email/list'),
      throwsA(isA<ApiFailure>().having((x) => x.code, 'code', 403)),
    );
  });
  test('HTML gateway response is a typed safe failure', () async {
    final api = ApiClient(
      Uri.parse('https://mail.example.com'),
      client: MockClient(
        (_) async => http.Response('<html>gateway</html>', 502),
      ),
    );
    await expectLater(
      api.request('GET', '/email/list'),
      throwsA(isA<ApiFailure>()),
    );
  });
}
