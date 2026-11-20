import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// A single email document with offline CSS and no addressable resources.
class MailHtmlDocument {
  final dom.Document _document;
  final Map<dom.Element, Uri> _images;
  final List<Uri> links;

  MailHtmlDocument._(this._document, this._images, this.links);

  static MailHtmlDocument? parse(String source) {
    if (source.trim().isEmpty) return null;
    const maxLength = 1024 * 1024;
    final document = html.parse(
      source.length > maxLength ? source.substring(0, maxLength) : source,
    );
    for (final node in document.querySelectorAll(
      'script, iframe, frame, frameset, object, embed, form, input, select, '
      'textarea, button, svg, math, audio, video, source, track, canvas, '
      'template, noscript, base, meta, link, plaintext, xmp',
    )) {
      node.remove();
    }
    for (final node in document.head!.nodes.toList()) {
      if (node is! dom.Element || node.localName != 'style') node.remove();
    }
    final body = document.body;
    if (body == null ||
        !body.nodes.any(
          (node) => switch (node) {
            dom.Text() => node.text.trim().isNotEmpty,
            dom.Element() => node.localName != 'style',
            _ => false,
          },
        )) {
      return null;
    }

    final images = <dom.Element, Uri>{};
    final links = <Uri>{};
    for (final node in document.querySelectorAll('*')) {
      final href = node.attributes['href'];
      final src = node.attributes['src'];
      node.attributes.removeWhere((key, _) {
        final name = key.toString().toLowerCase();
        return name.startsWith('on') ||
            const {
              'action',
              'background',
              'data',
              'download',
              'formaction',
              'href',
              'imagesrcset',
              'longdesc',
              'manifest',
              'ping',
              'poster',
              'src',
              'srcdoc',
              'srcset',
              'target',
              'xlink:href',
            }.contains(name);
      });
      if (node.localName == 'a') {
        final url = safeMailUrl(href);
        if (url != null) {
          node.attributes['href'] = url.toString();
          links.add(url);
        }
      }
      if (node.localName == 'img') {
        final url = safeMailUrl(src, image: true);
        if (url != null) images[node] = url;
      }
    }

    final policy = dom.Element.tag('meta')
      ..attributes.addAll({
        'http-equiv': 'Content-Security-Policy',
        'content':
            "default-src 'none'; img-src data:; "
            "style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
      });
    final viewport = dom.Element.tag('meta')
      ..attributes.addAll({
        'name': 'viewport',
        'content': 'width=device-width, initial-scale=1',
      });
    final defaults = dom.Element.tag('style')
      ..text = '''
        html { color-scheme: only light; background: white; }
        body { margin: 0; color: #202124; font: 16px/1.45 sans-serif; }
        table { max-width: 100%; }
        img { max-width: 100%; height: auto; }
      ''';
    document.head!.nodes.insertAll(0, [policy, viewport, defaults]);
    return MailHtmlDocument._(document, images, List.unmodifiable(links));
  }

  late final List<Uri> remoteImages = List.unmodifiable(_images.values.toSet());

  String render({Map<Uri, String> images = const {}}) {
    for (final MapEntry(key: node, value: url) in _images.entries) {
      final data = images[url];
      if (data == null) {
        node.attributes.remove('src');
      } else {
        node.attributes['src'] = data;
      }
    }
    return '<!doctype html>${_document.documentElement!.outerHtml}';
  }
}

Uri? safeMailUrl(String? value, {bool image = false}) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  if (!image && uri.scheme == 'mailto' && uri.path.contains('@')) return uri;
  return uri.host.isNotEmpty &&
          (uri.scheme == 'https' || (!image && uri.scheme == 'http'))
      ? uri
      : null;
}
