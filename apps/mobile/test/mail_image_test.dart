import 'package:cloud_mail/features/rich_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'an HTTPS image can redirect to a CDN without forwarding credentials',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) {
          return http.Response(
            '',
            302,
            headers: {'location': '//cdn.example.test/media.png'},
          );
        }
        return http.Response.bytes(
          [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      });
      addTearDown(client.close);
      final image = await fetchMailImage(
        client,
        Uri.parse('https://example.test/a'),
      );
      expect(image.mime, 'image/png');
      expect(requests.map((request) => request.url.toString()), [
        'https://example.test/a',
        'https://cdn.example.test/media.png',
      ]);
      expect(
        requests.every(
          (request) => !request.headers.containsKey('authorization'),
        ),
        true,
      );
      expect(requests.every((request) => !request.followRedirects), true);
    },
  );

  test('blocks redirects to cleartext and URLs with credentials', () async {
    for (final location in [
      'http://cdn.example.test/media.png',
      'https://someone:secret@cdn.example.test/media.png',
    ]) {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('', 302, headers: {'location': location});
      });
      addTearDown(client.close);
      await expectLater(
        fetchMailImage(client, Uri.parse('https://example.test/a')),
        throwsFormatException,
      );
      expect(requests, 1);
    }
  });
}
