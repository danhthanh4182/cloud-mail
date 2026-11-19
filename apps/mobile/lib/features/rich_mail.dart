import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

dom.Element? safeMailHtml(String source) {
  final document = html.parse(
    source.length > 160000 ? source.substring(0, 160000) : source,
  );
  for (final item in document.querySelectorAll(
    'script,style,head,iframe,object,embed,form,svg,video,audio,template,link,meta,[hidden]',
  )) {
    item.remove();
  }
  for (final item in document.querySelectorAll('[style]')) {
    final style = item.attributes['style']!.toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    if (style.contains('display:none') || style.contains('visibility:hidden')) {
      item.remove();
    }
  }
  return document.body;
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

class RichMailBody extends StatelessWidget {
  final dom.Element document;
  final bool showImages;
  const RichMailBody({
    super.key,
    required this.document,
    required this.showImages,
  });

  InlineSpan _span(dom.Node node, [int depth = 0]) {
    if (depth > 24) return const TextSpan();
    if (node is dom.Text) {
      return TextSpan(text: node.text.replaceAll(RegExp(r'\s+'), ' '));
    }
    if (node is! dom.Element) return const TextSpan();
    final name = node.localName;
    if (name == 'br') return const TextSpan(text: '\n');
    if (name == 'img') return TextSpan(text: node.attributes['alt'] ?? '');
    return TextSpan(
      style: switch (name) {
        'strong' || 'b' || 'th' => const TextStyle(fontWeight: FontWeight.bold),
        'em' || 'i' => const TextStyle(fontStyle: FontStyle.italic),
        'u' => const TextStyle(decoration: TextDecoration.underline),
        's' || 'del' => const TextStyle(decoration: TextDecoration.lineThrough),
        'code' || 'pre' => const TextStyle(fontFamily: 'monospace'),
        _ => null,
      },
      children: [
        if (name == 'li') const TextSpan(text: '• '),
        for (final child in node.nodes.take(400)) _span(child, depth + 1),
        if (['div', 'p', 'li', 'blockquote', 'h1', 'h2', 'h3'].contains(name))
          const TextSpan(text: '\n'),
      ],
    );
  }

  Widget _table(
    BuildContext context,
    dom.Element element,
    Widget Function(dom.Element) cellBody,
  ) {
    final rows = element
        .querySelectorAll('tr')
        .take(80)
        .map(
          (row) => row.children
              .where((cell) => ['td', 'th'].contains(cell.localName))
              .take(12)
              .toList(),
        )
        .toList();
    final columns = rows.fold(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (columns == 0) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(145),
        border: TableBorder.all(color: colors.outlineVariant),
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (var i = 0; i < columns; i++)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: i >= row.length
                        ? const SizedBox.shrink()
                        : cellBody(row[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Flush inline text in blocks so tables retain their position in the message.
    final blocks = <Widget>[];
    var inline = <InlineSpan>[];
    var images = 0;
    var visited = 0;
    Widget? remoteImage(dom.Element node) {
      if (!showImages || images >= 6) return null;
      final uri = safeMailUrl(node.attributes['src'], image: true);
      if (uri == null) return null;
      images++;
      return _RemoteMailImage(
        key: ValueKey('$images:$uri'),
        uri: uri,
        label: node.attributes['alt'] ?? '',
      );
    }

    Widget cellBody(dom.Element cell) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(_span(cell)),
        if (showImages)
          for (final img in cell.querySelectorAll('img[src]').take(6))
            if (remoteImage(img) case final Widget child) child,
      ],
    );

    void flush() {
      if (inline.isEmpty) return;
      blocks.add(
        Text.rich(
          TextSpan(children: inline),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
      inline = [];
    }

    void visit(dom.Node node, int depth) {
      if (depth > 24 || visited++ > 1500) return;
      if (node is dom.Element) {
        if (node.localName == 'table') {
          flush();
          blocks.add(_table(context, node, cellBody));
          return;
        }
        if (node.localName == 'img') {
          final image = remoteImage(node);
          if (image != null) {
            flush();
            blocks.add(image);
            return;
          }
        }
        if (node.querySelector('table,${showImages ? 'img' : 'table'}') !=
            null) {
          for (final child in node.nodes) {
            visit(child, depth + 1);
          }
          return;
        }
      }
      inline.add(_span(node));
    }

    for (final node in document.nodes) {
      visit(node, 0);
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: block),
      ],
    );
  }
}

class _RemoteMailImage extends StatefulWidget {
  final Uri uri;
  final String label;
  const _RemoteMailImage({super.key, required this.uri, required this.label});
  @override
  State<_RemoteMailImage> createState() => _RemoteMailImageState();
}

class _RemoteMailImageState extends State<_RemoteMailImage> {
  final client = http.Client();
  late final image = _fetch();

  Future<Uint8List> _fetch() async {
    const max = 2 * 1024 * 1024;
    final response = await client
        .send(http.Request('GET', widget.uri)..followRedirects = false)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 ||
        ![
          'image/png',
          'image/jpeg',
          'image/webp',
          'image/gif',
        ].contains(response.headers['content-type']?.split(';').first.trim()) ||
        (response.contentLength ?? 0) > max) {
      client.close();
      throw const FormatException('Unsupported image');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final part in response.stream.timeout(
      const Duration(seconds: 8),
    )) {
      if (bytes.length + part.length > max) {
        throw const FormatException('Image too large');
      }
      bytes.add(part);
    }
    return bytes.takeBytes();
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: image,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return Image.memory(
          snapshot.data!,
          cacheWidth: 1000,
          semanticLabel: widget.label,
          errorBuilder: (_, _, _) => Text(widget.label),
        );
      }
      if (snapshot.hasError) return Text(widget.label);
      return const LinearProgressIndicator();
    },
  );
}
