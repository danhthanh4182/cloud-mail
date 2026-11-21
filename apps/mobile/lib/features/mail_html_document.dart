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
      'textarea, button, svg, math, audio, video, track, canvas, '
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

    final imageUrls = {
      for (final image in document.querySelectorAll('img'))
        image: mailImageUrl(image),
    };
    final images = <dom.Element, Uri>{};
    final links = <Uri>{};
    for (final node in document.querySelectorAll('*')) {
      final href = node.attributes['href'];
      final imageUrl = imageUrls[node];
      node.attributes.removeWhere((key, _) {
        final name = key.toString().toLowerCase();
        return name.startsWith('on') ||
            const {
              'action',
              'background',
              'data',
              'data-src',
              'data-srcset',
              'data-original',
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
      if (imageUrl != null) images[node] = imageUrl;
    }

    for (final source in document.querySelectorAll('source')) {
      source.remove();
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
  final input = value?.trim() ?? '';
  final uri = Uri.tryParse(
    image && input.startsWith('//') ? 'https:$input' : input,
  );
  if (uri == null || uri.authority.contains('@')) return null;
  if (!image && uri.scheme == 'mailto' && uri.path.contains('@')) return uri;
  return uri.host.isNotEmpty &&
          (uri.scheme == 'https' || (!image && uri.scheme == 'http'))
      ? uri
      : null;
}

final _hiddenMailImage = RegExp(
  r'(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*hidden|mso-hide\s*:\s*all)\s*(?:!important\s*)?(?:;|$)',
  caseSensitive: false,
);

Uri? mailImageUrl(dom.Element image) {
  for (dom.Element? node = image; node != null; node = node.parent) {
    if (node.attributes.containsKey('hidden') ||
        _hiddenMailImage.hasMatch(node.attributes['style'] ?? '')) {
      return null;
    }
  }
  final tinyDimension = RegExp(r'^(?:0|1)(?:px)?$', caseSensitive: false);
  if (['height', 'width'].any(
    (size) => tinyDimension.hasMatch(image.attributes[size]?.trim() ?? ''),
  )) {
    return null;
  }
  final attrs = image.attributes;
  for (final src in [attrs['src'], attrs['data-src'], attrs['data-original']]) {
    final url = safeMailUrl(src, image: true);
    if (url != null) return url;
  }
  final picture = image.parent;
  for (final list in [
    attrs['srcset'],
    attrs['data-srcset'],
    if (picture?.localName == 'picture')
      for (final source in picture!.children)
        if (source.localName == 'source') source.attributes['srcset'],
  ]) {
    if (list == null || list.trimLeft().startsWith('data:')) continue;
    for (final candidate in list.split(',')) {
      final url = safeMailUrl(
        candidate.trim().split(RegExp(r'\s+')).first,
        image: true,
      );
      if (url != null) return url;
    }
  }
  return null;
}
