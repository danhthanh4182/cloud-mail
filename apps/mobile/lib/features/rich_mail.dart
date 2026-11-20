import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'mail_html_document.dart';

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

  Iterable<dom.Element> _tableRows(dom.Element table) sync* {
    for (final child in table.children) {
      if (child.localName == 'tr') yield child;
      if (['thead', 'tbody', 'tfoot'].contains(child.localName)) {
        yield* child.children.where((row) => row.localName == 'tr');
      }
    }
  }

  bool _isDataTable(dom.Element table, List<List<dom.Element>> rows) {
    final role = table.attributes['role']?.trim().toLowerCase();
    if (role == 'presentation' || role == 'none') return false;
    if (role == 'table' || role == 'grid' || role == 'treegrid') return true;
    if (table.children.any((child) => child.localName == 'caption') ||
        rows.any((row) => row.any((cell) => cell.localName == 'th'))) {
      return true;
    }

    // Regular headerless tables can have missing values. A fully populated
    // row distinguishes their columns from recurring empty spacer cells.
    return rows.length >= 2 &&
        rows.first.length >= 2 &&
        rows.any((row) => row.every((cell) => cell.text.trim().isNotEmpty)) &&
        rows.every(
          (row) =>
              row.length == rows.first.length &&
              row.every(
                (cell) =>
                    !cell.attributes.containsKey('colspan') &&
                    !cell.attributes.containsKey('rowspan') &&
                    cell.querySelector('table') == null,
              ),
        );
  }

  Widget _table(
    BuildContext context,
    List<List<dom.Element>> rows,
    Widget Function(dom.Element) cellBody,
  ) {
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

    List<Widget> render(
      Iterable<dom.Node> nodes,
      int depth,
      TextStyle? textStyle,
    ) {
      final blocks = <Widget>[];
      var inline = <InlineSpan>[];
      void flush() {
        if (inline.isEmpty) return;
        final span = TextSpan(children: inline);
        if (span.toPlainText().trim().isNotEmpty) {
          blocks.add(Text.rich(span, style: textStyle));
        }
        inline = [];
      }

      void visit(dom.Node node, int depth) {
        if (depth > 24 || visited++ > 1500) return;
        if (node is dom.Element) {
          if (node.localName == 'table') {
            final rows = _tableRows(node)
                .take(80)
                .map(
                  (row) => row.children
                      .where((cell) => ['td', 'th'].contains(cell.localName))
                      .take(12)
                      .toList(),
                )
                .where((row) => row.isNotEmpty)
                .toList();
            flush();
            for (final caption in node.children.where(
              (child) => child.localName == 'caption',
            )) {
              for (final child in caption.nodes) {
                visit(child, depth + 1);
              }
              flush();
            }
            if (_isDataTable(node, rows)) {
              blocks.add(
                _table(
                  context,
                  rows,
                  (cell) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: render(
                      cell.nodes,
                      depth + 1,
                      cell.localName == 'th'
                          ? const TextStyle(fontWeight: FontWeight.bold)
                          : null,
                    ),
                  ),
                ),
              );
            } else {
              for (final row in rows) {
                for (final cell in row) {
                  for (final child in cell.nodes) {
                    visit(child, depth + 1);
                  }
                  flush();
                }
              }
            }
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
          if (node.querySelector(showImages ? 'table,img' : 'table') != null) {
            for (final child in node.nodes) {
              visit(child, depth + 1);
            }
            return;
          }
        }
        inline.add(_span(node));
      }

      for (final node in nodes) {
        visit(node, depth);
      }
      flush();
      return blocks;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in render(
          document.nodes,
          0,
          Theme.of(context).textTheme.bodyLarge,
        ))
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
    final image = await fetchMailImage(client, widget.uri);
    return image.bytes;
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

Future<({String mime, Uint8List bytes})> fetchMailImage(
  http.Client client,
  Uri uri,
) async {
  const maxBytes = 2 * 1024 * 1024;
  const timeout = Duration(seconds: 8);
  final response = await client
      .send(http.Request('GET', uri)..followRedirects = false)
      .timeout(timeout);
  final mime = response.headers['content-type']?.split(';').first.trim();
  if (response.statusCode != 200 ||
      mime == null ||
      !const {
        'image/png',
        'image/jpeg',
        'image/webp',
        'image/gif',
      }.contains(mime) ||
      (response.contentLength ?? 0) > maxBytes) {
    final subscription = response.stream.listen(null);
    await subscription.cancel();
    throw const FormatException('Unsupported image');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final part in response.stream.timeout(timeout)) {
    if (bytes.length + part.length > maxBytes) {
      throw const FormatException('Image too large');
    }
    bytes.add(part);
  }
  return (mime: mime, bytes: bytes.takeBytes());
}
