import 'dart:async';
import 'dart:convert';

import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';
import 'package:cloud_mail/domain/mail.dart';
import 'package:cloud_mail/domain/mail_sync.dart';
import 'package:cloud_mail/domain/smart_mail.dart';
import 'package:cloud_mail/features/mail_html_document.dart';
import 'package:cloud_mail/features/rich_mail.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'session_test.dart' show MemoryVault;

http.Response envelope(Object? data, {int code = 200}) => http.Response(
  jsonEncode({'code': code, 'data': data}),
  200,
  headers: {'content-type': 'application/json'},
);

AppController signedIn(MemoryVault vault, MockClient client) =>
    AppController(vault)
      ..api = ApiClient(Uri.parse('https://example.test'), client: client)
      ..profile = {'userId': 1}
      ..addresses = [const MailAddress(id: 10, email: 'owner@example.test')]
      ..capabilities = const Capabilities(organization: true, draftSync: true);

Map<String, Object?> replica(
  MailDraft draft,
  int revision, {
  bool deleted = false,
}) => {
  'draftId': draft.id,
  'revision': revision,
  'deleted': deleted,
  'payload': deleted ? null : draftReplica(draft),
};

void main() {
  test('remote revision replaces a clean draft, and a dirty edit gets a separate copy', () async {
    final newDraft = MailDraft(
      id: 'draft-one',
      accountId: 10,
      body: 'Remote edit',
    );
    var row = replica(newDraft, 2);
    final controller = signedIn(
      MemoryVault(),
      MockClient(
        (_) async => envelope({
          'list': [row],
        }),
      ),
    );
    addTearDown(controller.dispose);
    final local = MailDraft(
      id: 'draft-one',
      accountId: 10,
      revision: 1,
      body: 'Initial',
    );
    local.syncStamp = draftStamp(local);
    await controller.saveDraft(local);
    await controller.syncDrafts();
    await controller.syncDrafts();
    expect(controller.drafts.map((x) => x.body), ['Remote edit']);
    expect(controller.drafts.single.revision, 2);

    controller.drafts.single.body = 'Changed on this device';
    newDraft.body = 'Another remote edit';
    row = replica(newDraft, 3);
    await controller.syncDrafts();
    expect(controller.drafts.map((x) => x.body), [
      'Changed on this device',
      'Another remote edit',
    ]);
    expect(controller.drafts.first.conflictCopy, true);
    expect(controller.drafts.first.id, isNot('draft-one'));
    row = replica(newDraft, 4, deleted: true);
    await controller.syncDrafts();
    expect(controller.drafts.single.body, 'Changed on this device');
  });

  test('deleting during draft upload uses the acknowledged revision', () async {
    final received = Completer<void>(), finish = Completer<void>();
    final draft = MailDraft(id: 'draft-one', accountId: 10, body: 'One');
    var remote = <Object>[];
    final controller = signedIn(
      MemoryVault(),
      MockClient((request) async {
        switch (request.method) {
          case 'PUT':
            received.complete();
            await finish.future;
            remote = [replica(draft, 1)];
            return envelope({'revision': 1});
          case 'DELETE':
            expect(request.url.queryParameters['revision'], '1');
            remote = [];
            return envelope(null);
          default:
            return envelope({'list': remote});
        }
      }),
    );
    addTearDown(controller.dispose);
    await controller.saveDraft(draft);
    final sync = controller.syncDrafts();
    await received.future;
    await controller.deleteDraft(draft);
    finish.complete();
    await sync;
    expect(controller.draftDeletes[draft.id], 1);
    await controller.syncDrafts();
    expect(controller.drafts, isEmpty);
    expect(remote, isEmpty);
  });

  test('offline edits and cache time survive reopen; stale changes stay visible as conflicts', () async {
    final vault = MemoryVault();
    final mail = const MailMessage(
      id: 4,
      accountId: 10,
      subject: 'Fixture',
      version: 3,
    );
    var connected = true;
    var writes = 0;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (!connected) throw http.ClientException('Disconnected');
      if (path.endsWith('/state')) {
        writes++;
        expect(jsonDecode(request.body), {'version': 3, 'folder': 'archive'});
        return envelope(null, code: 409);
      }
      if (path.endsWith('/login')) return envelope({'token': 'fixture'});
      if (path.endsWith('/my/loginUserInfo')) return envelope({'userId': 1});
      if (path.endsWith('/account/list')) {
        return envelope([
          {'accountId': 10, 'email': 'owner@example.test'},
        ]);
      }
      if (path.endsWith('/mobile/capabilities')) {
        return envelope({'version': 2, 'organization': true});
      }
      return envelope({
        'list': [mail.toJson()],
        'hasMore': false,
      });
    });
    AppController open() => AppController(
      vault,
      apiFactory: (origin, token, language) =>
          ApiClient(origin, token: token, language: language, client: client),
    );
    final one = open();
    await one.login('https://example.test', 'owner@example.test', 'fixture');
    final syncedAt = one.lastServerSync!;
    one.offline = true;
    await one.organize(mail, target: 'archive');
    connected = false;
    final two = open();
    addTearDown(two.dispose);
    await two.initialize();
    expect(two.offline, true);
    expect(two.pendingEdits.single.patch['folder'], 'archive');
    expect(two.lastServerSync, syncedAt);
    expect(two.messages, isEmpty);
    connected = true;
    await two.loadMessages();
    expect(two.pendingEdits.single.conflict, true);
    expect(two.messages.single.folder, 'inbox');
    await two.loadMessages();
    expect(writes, 1);
    one.dispose();
  });

  test(
    'natural language search previews sender and date without hosted AI',
    () {
      final now = DateTime.utc(2026, 11, 19, 12);
      expect(
        interpretMailSearch('Thư từ owner@example.test hôm qua', now: now),
        {
          'field': 'senderAddress',
          'text': 'owner@example.test',
          'startDate': '2026-11-18',
          'endDate': '2026-11-18',
        },
      );
      expect(interpretMailSearch('find body: invoice last week', now: now), {
        'field': 'content',
        'text': 'invoice',
        'startDate': '2026-11-13',
        'endDate': '2026-11-19',
      });
    },
  );

  testWidgets('table contents render and images load only after consent', (
    tester,
  ) async {
    const source =
        '<table><tr><th>Item</th><th>Amount</th></tr>'
        '<tr><td><b>Total due</b><img src="https://example.test/a.png"></td><td>12 USD</td></tr></table>'
        '<script>malicious content</script><a href="javascript:bad()">link</a>';
    final document = safeMailHtml(source)!;
    expect(
      safeMailUrl(document.querySelector('a')!.attributes['href']),
      isNull,
    );
    var downloads = 0;
    final client = MockClient((request) async {
      downloads++;
      expect(request.headers.keys, isNot(contains('Authorization')));
      return http.Response.bytes(Uint8List(0), 404);
    });
    Future<void> render(bool show) => http.runWithClient(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichMailBody(document: document, showImages: show),
          ),
        ),
      ),
      () => client,
    );
    await render(false);
    expect(find.byType(Table), findsOneWidget);
    expect(
      find.textContaining('Total due', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('malicious content', findRichText: true),
      findsNothing,
    );
    expect(downloads, 0);
    await render(true);
    expect(downloads, 1);
  });

  test('declined Android permission does not register a push device', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pushChannel, (call) async {
      if (call.method == 'requestPermission') return false;
      throw PlatformException(code: 'unexpected');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(pushChannel, null));
    var calls = 0;
    final controller = signedIn(
      MemoryVault(),
      MockClient((_) async {
        calls++;
        return envelope(null);
      }),
    )..pushConfigured = true;
    addTearDown(controller.dispose);
    await controller.enablePush();
    expect(controller.pushDevice, isNull);
    expect(calls, 0);
    expect(controller.pushStatus, isNotEmpty);
  });
}
