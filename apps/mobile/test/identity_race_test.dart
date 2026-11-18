import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';
import 'package:cloud_mail/domain/mail.dart';

import 'session_test.dart' show MemoryVault;

class BlockingVault extends MemoryVault {
  final blocked = Completer<void>(), release = Completer<void>();
  bool armed = false;
  @override
  Future<void> write(String key, String value) async {
    if (armed && key.startsWith('drafts:')) {
      armed = false;
      blocked.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

void main() {
  test('a send cannot adopt a new session during draft persistence', () async {
    final vault = BlockingVault();
    var sentAsB = 0;
    final a = ApiClient(
      Uri.parse('https://a.example.com'),
      token: 'A',
      client: MockClient(
        (r) async =>
            http.Response('{"code":200,"data":{"state":"accepted"}}', 200),
      ),
    );
    final b = ApiClient(
      Uri.parse('https://b.example.com'),
      token: 'B',
      client: MockClient((r) async {
        sentAsB++;
        return http.Response('{"code":200,"data":{"state":"accepted"}}', 200);
      }),
    );
    final app = AppController(vault)
      ..api = a
      ..profile = {'userId': 1}
      ..capabilities = const Capabilities(safeSend: true);
    vault.armed = true;
    final sending = app.sendDraft(
      MailDraft(accountId: 10, to: 'controlled@example.com', body: 'Fixture'),
    );
    final failed = expectLater(sending, throwsA(isA<ApiFailure>()));
    await vault.blocked.future;
    final logout = app.logout();
    app.api = b;
    app.profile = {'userId': 2};
    vault.release.complete();
    await failed;
    await logout;
    expect(sentAsB, 0);
    app.dispose();
  });
  test('late reconciliation never inserts a foreign draft into the current session', () async {
    final response = Completer<http.Response>();
    final app = AppController(MemoryVault())
      ..api = ApiClient(
        Uri.parse('https://a.example.com'),
        client: MockClient((_) => response.future),
      )
      ..profile = {'userId': 1};
    final draft = MailDraft(
      accountId: 10,
      body: 'private A',
      requestKey: 'request-123456',
      sendState: 'unknown',
    );
    final pending = app.reconcile(draft);
    final failed = expectLater(pending, throwsA(isA<ApiFailure>()));
    final logout = app.logout();
    app.api = ApiClient(Uri.parse('https://b.example.com'));
    app.profile = {'userId': 2};
    response.complete(
      http.Response('{"code":200,"data":{"state":"unknown"}}', 200),
    );
    await failed;
    await logout;
    expect(app.drafts, isEmpty);
    app.dispose();
  });
}
