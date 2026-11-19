import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_mail/app.dart';
import 'package:cloud_mail/app_controller.dart';
import 'package:cloud_mail/data/api.dart';
import 'package:cloud_mail/domain/mail.dart';
import 'package:cloud_mail/features/reader.dart';

import 'session_test.dart' show MemoryVault;

void main() {
  testWidgets('capture real native widgets with fictional mail', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('CAPTURE_NATIVE')) return;
    final font = File(
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    await tester.runAsync(() async {
      if (await font.exists()) {
        final loader = FontLoader('Roboto')
          ..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          );
        await loader.load();
      }
    });
    await tester.runAsync(() async {
      final iconFont = File(
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await iconFont.exists()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(ByteData.sublistView(await iconFont.readAsBytes())),
          );
        await loader.load();
      }
    });
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppController(MemoryVault())
      ..ready = true
      ..language = 'vi'
      ..theme = 'light';
    final key = GlobalKey();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/native-previews').create(recursive: true);
      await File('build/native-previews/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: CloudMailApp(controller: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => capture('login-light'));
    state.api = ApiClient(Uri.parse('https://mail.example.com'));
    state.profile = {
      'userId': 1,
      'email': 'thanh@example.com',
      'name': 'Thanh',
    };
    state.addresses = [const MailAddress(id: 10, email: 'thanh@example.com')];
    state.messages = [
      const MailMessage(
        id: 100,
        sender: 'security@example.com',
        name: 'Example Security',
        subject: 'Mã xác nhận đăng nhập',
        text: 'Mã xác nhận của bạn là 083741. Không chia sẻ mã này.',
        time: '2026-11-18 10:20:30',
      ),
      const MailMessage(
        id: 99,
        sender: 'team@example.com',
        name: 'Product team',
        subject: 'Bản thiết kế đã sẵn sàng',
        text: 'Thanh ơi, bạn có thể xem bản thiết kế mới và góp ý trước thứ Sáu nhé.',
        time: '2026-11-18 09:15:00',
        starred: true,
      ),
      const MailMessage(
        id: 98,
        sender: 'billing@example.com',
        name: 'Example Cloud',
        subject: 'Hóa đơn tháng 11',
        text: 'Hóa đơn mới đã được tạo. Bạn có thể kiểm tra chi tiết trong tài khoản.',
        time: '2026-11-17 18:00:00',
        unread: false,
      ),
    ];
    state.changed();
    await tester.pumpAndSettle();
    await tester.runAsync(() => capture('inbox-light'));
    state.theme = 'dark';
    state.changed();
    await tester.pumpAndSettle();
    await tester.runAsync(() => capture('inbox-dark'));
    unawaited(
      Navigator.of(tester.element(find.text('Mã xác nhận đăng nhập'))).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            state: state,
            mail: const MailMessage(
              id: 101,
              sender: 'security@example.com',
              name: 'Example Security',
              subject: 'Mã xác nhận đăng nhập',
              recipients: [MailParticipant('thanh@example.com', name: 'Thanh')],
              senderDomainAuthenticated: true,
              labels: ['Bảo mật', 'Tài khoản'],
              content: '''
                <table role="presentation"><tr><td></td><td>
                  <table><tr><td>Chào Thanh,</td></tr>
                    <tr><td>Mã xác nhận của bạn là <b>083741</b>.</td></tr>
                    <tr><td>Nếu bạn không yêu cầu đăng nhập, hãy bỏ qua thư này.</td></tr>
                  </table>
                </td></tr></table>
              ''',
              time: '2026-11-18 10:20:30',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => capture('reader-dark'));
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
