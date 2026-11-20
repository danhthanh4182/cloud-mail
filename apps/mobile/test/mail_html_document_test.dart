import 'package:cloud_mail/features/mail_html_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  test(
    'preserves responsive marketing tables and inline verification actions',
    () {
      final mail = MailHtmlDocument.parse('''
      <html lang="vi">
      <head><style>
        .offer { background: #d52c0d; color: white }
        @media (max-width: 480px) { .desktop-only { display: none } }
      </style></head>
      <body style="background-color: #fff">
        <table role="presentation" width="600"><tr>
          <td>Shopee Mall</td><td class="desktop-only">Thời Trang</td>
        </tr><tr><td colspan="2">
          <table role="presentation"><tr>
            <td>First product</td><td>Second product</td>
          </tr></table>
        </td></tr></table>
        <a class="offer" style="border-radius: 12px; padding: 16px"
           href="https://example.test/account">This wasn't me</a>
      </body></html>
    ''')!;
      final rendered = html.parse(mail.render());
      expect(rendered.querySelectorAll('table'), hasLength(2));
      expect(rendered.querySelectorAll('tr').first.children, hasLength(2));
      expect(rendered.querySelector('td[colspan="2"]'), isNotNull);
      final css = rendered
          .querySelectorAll('style')
          .map((el) => el.text)
          .join();
      expect(css, contains('@media (max-width: 480px)'));
      expect(rendered.body!.attributes['style'], 'background-color: #fff');
      final action = rendered.querySelector('a.offer')!;
      expect(action.text, "This wasn't me");
      expect(action.attributes['style'], contains('border-radius: 12px'));
      expect(action.attributes['href'], 'https://example.test/account');
      expect(rendered.documentElement!.attributes['lang'], 'vi');
    },
  );

  test('strips active content and only applies approved img sources', () {
    final mail = MailHtmlDocument.parse('''
      <base href="https://example.test/">
      <meta http-equiv="refresh" content="0;url=https://example.test/redirect">
      <link rel="stylesheet" href="https://example.test/stylesheet">
      <body onload="run()">
        <style>@import url(https://example.test/unrequested.css);</style>
        <script>run()</script>
        <iframe srcdoc="<p>External content</p>"></iframe>
        <form action="https://example.test/form"><input autofocus></form>
        <a href="java&#x09;script:bad()">unsafe</a>
        <a href="mailto:help@example.test" target="_blank"
           ping="https://example.test/tap" onclick="run()">contact</a>
        <img src="https://example.test/banner.png" alt="Banner" width="480"
             srcset="https://example.test/alternate.png 2x" onerror="run()">
        <img src="data:image/png;base64,AUTHOR_DATA" alt="author data">
        <img src="http://example.test/cleartext.png">
        <picture><source srcset="https://example.test/picture.png"><img
          src="https://example.test/banner.png" alt="Repeated"></picture>
      </body>
    ''')!;
    final target = Uri.parse('https://example.test/banner.png');
    expect(mail.remoteImages, [target]);

    final offline = html.parse(mail.render());
    expect(
      offline.querySelector('[src], [srcset], [onload], [onerror]'),
      isNull,
    );
    expect(offline.querySelector('base, link, script, iframe, form'), isNull);
    expect(offline.querySelector('meta[http-equiv="refresh"]'), isNull);
    expect(offline.querySelector('a')!.attributes['href'], isNull);
    final contact = offline.querySelectorAll('a').last;
    expect(contact.attributes, {'href': 'mailto:help@example.test'});
    expect(
      offline
          .querySelector('meta[http-equiv="Content-Security-Policy"]')!
          .attributes['content'],
      contains("default-src 'none'; img-src data:"),
    );

    final withImages = html.parse(
      mail.render(images: {target: 'data:image/png;base64,APP_DATA'}),
    );
    expect(
      withImages
          .querySelectorAll('img[src]')
          .map((image) => image.attributes['src']),
      ['data:image/png;base64,APP_DATA', 'data:image/png;base64,APP_DATA'],
    );
    expect(
      withImages.querySelector('img[alt="Banner"]')!.attributes['width'],
      '480',
    );
    expect(html.parse(mail.render()).querySelector('img[src]'), isNull);
  });

  test('empty and non-displayable mail use the text body', () {
    expect(MailHtmlDocument.parse(''), isNull);
    expect(MailHtmlDocument.parse('<style>p { color: red }</style>'), isNull);
    expect(MailHtmlDocument.parse('<script>ignored()</script>'), isNull);
  });
}
