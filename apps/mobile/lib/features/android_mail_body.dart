import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'mail_html_document.dart';
import 'rich_mail.dart';

class MailBody extends StatefulWidget {
  final MailHtmlDocument document;
  final bool showImages;
  final Widget fallback;
  final ValueChanged<Uri> onLink;

  const MailBody({
    super.key,
    required this.document,
    required this.showImages,
    required this.fallback,
    required this.onLink,
  });

  @override
  State<MailBody> createState() => _MailBodyState();
}

class _MailBodyState extends State<MailBody>
    with AutomaticKeepAliveClientMixin<MailBody> {
  static const _viewType = 'cloud_mail/html_body';
  MethodChannel? _channel;
  http.Client? _imageClient;
  var _needsDocument = true;
  int? _lastZoom;
  var _images = <Uri, String>{};
  var _height = 64.0;
  var _available = !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_updateView());
  }

  @override
  void didUpdateWidget(covariant MailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document ||
        oldWidget.showImages != widget.showImages) {
      _needsDocument = true;
      _images = {};
      _loadImages();
      unawaited(_updateView());
    }
  }

  void _loadImages() {
    _imageClient?.close();
    _imageClient = null;
    if (!_available || !widget.showImages) return;
    final candidates = widget.document.remoteImages.take(16).toList();
    if (candidates.isEmpty) return;
    final client = _imageClient = http.Client();
    Future<void> load() async {
      const maxTotal = 8 * 1024 * 1024;
      final loaded = <Uri, String>{};
      var total = 0;
      for (
        var start = 0;
        start < candidates.length && total < maxTotal;
        start += 4
      ) {
        final batch = candidates.skip(start).take(4);
        await Future.wait(
          batch.map((url) async {
            try {
              final image = await fetchMailImage(
                client,
                url,
              ).timeout(const Duration(seconds: 10));
              if (total + image.bytes.length <= maxTotal) {
                total += image.bytes.length;
                loaded[url] =
                    'data:${image.mime};base64,${base64Encode(image.bytes)}';
              }
            } on Exception {
              // The email's alt text still displays when an image is unavailable.
            }
          }),
        );
        if (!mounted || _imageClient != client) return;
      }
      client.close();
      _imageClient = null;
      setState(() {
        _images = loaded;
        _needsDocument = true;
      });
      await _updateView();
    }

    unawaited(load());
  }

  Future<void> _updateView() async {
    final channel = _channel;
    if (channel == null || !_available) return;
    final zoom = (MediaQuery.textScalerOf(context).scale(16) / 16 * 100)
        .round();
    final html = _needsDocument
        ? widget.document.render(images: _images)
        : null;
    if (html == null && zoom == _lastZoom) return;
    _needsDocument = false;
    _lastZoom = zoom;
    try {
      await channel.invokeMethod<void>('render', {'html': html, 'zoom': zoom});
    } on PlatformException {
      _useFallback();
    } on MissingPluginException {
      _useFallback();
    }
  }

  void _useFallback() {
    if (!mounted || !_available) return;
    _imageClient?.close();
    _imageClient = null;
    setState(() => _available = false);
  }

  void _onCreated(int id) {
    if (!mounted) return;
    final channel = _channel = MethodChannel('$_viewType/$id');
    channel.setMethodCallHandler((call) async {
      if (!mounted || !_available) return;
      switch (call.method) {
        case 'height':
          final height = (call.arguments as num).toDouble();
          if (height > 0 && height != _height) setState(() => _height = height);
        case 'link':
          final url = safeMailUrl(call.arguments as String?);
          if (url != null) widget.onLink(url);
        case 'unavailable':
          _useFallback();
      }
    });
    unawaited(_updateView());
  }

  @override
  void dispose() {
    _imageClient?.close();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  // Keep consent-loaded images with the reader when the body scrolls offscreen.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_available) return widget.fallback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_imageClient != null) const LinearProgressIndicator(),
        SizedBox(
          height: _height,
          child: PlatformViewLink(
            viewType: _viewType,
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<HorizontalDragGestureRecognizer>(
                  HorizontalDragGestureRecognizer.new,
                ),
              },
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
            onCreatePlatformView: (params) {
              return PlatformViewsService.initExpensiveAndroidView(
                  id: params.id,
                  viewType: _viewType,
                  layoutDirection: Directionality.of(context),
                  onFocus: () => params.onFocusChanged(true),
                )
                ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                ..addOnPlatformViewCreatedListener(_onCreated)
                ..create();
            },
          ),
        ),
      ],
    );
  }
}
