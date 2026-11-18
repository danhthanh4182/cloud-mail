import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_mail/domain/mail.dart';

void main() {
  final fixtures = jsonDecode(
    File('../../specs/001-native-mail/contracts/fixtures/otp.json')
        .readAsStringSync(),
  ) as List;
  for (final f in fixtures) {
    test(
      'OTP: ${f['name']}',
      () => expect(extractOtp(f['subject'], f['body']), f['expected']),
    );
  }
  test('recipients normalize duplicates and reject malformed addresses', () {
    expect(parseRecipients('A@example.com; b@example.com, a@example.com'), [
      'A@example.com',
      'b@example.com',
    ]);
    expect(() => parseRecipients('not-an-email'), throwsFormatException);
  });
  test('server origins require HTTPS without credentials or query tokens', () {
    expect(
      validateServer('https://mail.example.com/api/').toString(),
      'https://mail.example.com',
    );
    expect(
      () => validateServer('http://mail.example.com'),
      throwsFormatException,
    );
    expect(
      () => validateServer('https://secret:pass@mail.example.com'),
      throwsFormatException,
    );
    expect(
      () => validateServer('https://mail.example.com/?token=x'),
      throwsFormatException,
    );
  });
}
