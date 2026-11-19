import 'package:cloud_mail/features/rich_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> renderMail(WidgetTester tester, String source) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RichMailBody(
            document: safeMailHtml(source)!,
            showImages: false,
          ),
        ),
      ),
    ),
  );
}

Finder mailText(String text) => find.textContaining(text, findRichText: true);

Finder horizontalScroll() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.right,
);

void main() {
  testWidgets('nested verification mail reads once at full available width', (
    tester,
  ) async {
    await renderMail(tester, '''
      <table width="640" cellspacing="0" cellpadding="0">
        <tr><td width="30">&nbsp;</td><td>
          <table role="presentation">
            <tr><td colspan="2"><p>Confirm your example account</p></td></tr>
            <tr><td></td><td>
              <table><tr><td><strong>Verification code</strong><br>012345</td></tr></table>
            </td></tr>
            <tr><td colspan="2">If you did not request this, ignore the message.</td></tr>
            <tr style="display: none !important"><td>012345</td></tr>
          </table>
        </td><td>&nbsp;</td></tr>
      </table>
    ''');
    final intro = mailText('Confirm your example account');
    final code = mailText('012345');
    final footer = mailText('ignore the message');
    expect(intro, findsOneWidget);
    expect(code, findsOneWidget);
    expect(footer, findsOneWidget);
    final contents = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(RichMailBody),
            matching: find.byType(RichText),
          ),
        )
        .map((widget) => widget.text.toPlainText())
        .join('\n');
    for (final phrase in [
      'Confirm your example account',
      'Verification code',
      '012345',
      'ignore the message',
    ]) {
      expect(RegExp(phrase).allMatches(contents), hasLength(1));
    }
    expect(tester.getTopLeft(intro).dx, tester.getTopLeft(code).dx);
    expect(tester.getTopLeft(intro).dy, lessThan(tester.getTopLeft(code).dy));
    expect(tester.getTopLeft(code).dy, lessThan(tester.getTopLeft(footer).dy));
    expect(tester.getTopRight(footer).dx, lessThanOrEqualTo(344));
    expect(find.byType(Table), findsNothing);
    expect(horizontalScroll(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'layout wrappers keep a nested data table independently scrollable',
    (tester) async {
      await renderMail(tester, '''
      <table role="presentation"><tr><td>
        <p>Receipt summary</p>
        <table>
          <caption>Purchased items</caption>
          <thead><tr><th>Item</th><th>Quantity</th><th>Amount</th><th>Status</th></tr></thead>
          <tbody>
            <tr><td>Notebook</td><td>2</td><td>12 USD</td><td>Ready</td></tr>
            <tr><td>Pencil</td><td>2</td><td>4 USD</td><td>Ready</td></tr>
          </tbody>
        </table>
      </td></tr></table>
    ''');
      expect(mailText('Receipt summary'), findsOneWidget);
      expect(mailText('Purchased items'), findsOneWidget);
      expect(mailText('Notebook'), findsOneWidget);
      expect(mailText('Ready'), findsNWidgets(2));
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children, hasLength(3));
      expect(table.children.first.children, hasLength(4));
      final scroll = tester.state<ScrollableState>(horizontalScroll());
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(horizontalScroll(), const Offset(-230, 0));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('headerless data rows keep their columns with missing values', (
    tester,
  ) async {
    await renderMail(tester, '''
      <table>
        <tr><td>Subtotal</td><td>12 USD</td></tr>
        <tr><td>Discount</td><td></td></tr>
      </table>
    ''');
    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(2));
    expect(table.children.first.children, hasLength(2));
    expect(table.children.last.children, hasLength(2));
  });
}
