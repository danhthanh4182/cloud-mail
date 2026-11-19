import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/mail.dart';

class ApiFailure implements Exception {
  final int code;
  final String message;
  const ApiFailure(this.code, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  final Uri origin;
  final http.Client _client;
  String token, language;
  ApiClient(
    this.origin, {
    http.Client? client,
    this.token = '',
    this.language = 'vi',
  }) : _client = client ?? http.Client();
  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    Future<void>? abort,
    void Function(int received, int? total)? progress,
    int maxBytes = 18 * 1024 * 1024,
  }) async {
    if (!path.startsWith('/') || path.contains('://')) {
      throw const ApiFailure(400, 'Invalid API path');
    }
    final uri = origin.replace(path: '/api$path', queryParameters: query);
    final request = http.AbortableRequest(method, uri, abortTrigger: abort)
      ..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'accept-language': language,
      if (token.isNotEmpty) 'Authorization': token,
      ...?headers,
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final stream = await _client
          .send(request)
          .timeout(const Duration(seconds: 35));
      if (stream.contentLength != null && stream.contentLength! > maxBytes) {
        throw const ApiFailure(413, 'Response exceeds mobile limit');
      }
      final bytes = BytesBuilder();
      await for (final chunk in stream.stream.timeout(
        const Duration(seconds: 35),
      )) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          throw const ApiFailure(413, 'Response exceeds mobile limit');
        }
        progress?.call(bytes.length, stream.contentLength);
      }
      return http.Response.bytes(
        bytes.takeBytes(),
        stream.statusCode,
        headers: stream.headers,
      );
    } on TimeoutException {
      throw const ApiFailure(
        0,
        'Connection timed out. A send may still be processing.',
      );
    } on http.RequestAbortedException {
      throw const ApiFailure(499, 'Download canceled');
    } on http.ClientException {
      throw const ApiFailure(0, 'Cannot connect to the mail server.');
    }
  }

  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final response = await _send(
      method,
      path,
      body: body,
      query: query,
      headers: headers,
    );
    Map<String, dynamic>? envelope;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) envelope = decoded;
    } catch (_) {}
    if (response.statusCode >= 300) {
      throw ApiFailure(
        response.statusCode,
        'Mail server returned HTTP ${response.statusCode}.',
      );
    }
    if (envelope == null) {
      throw const ApiFailure(
        502,
        'The server returned an invalid API response.',
      );
    }
    final code = asInt(envelope['code']);
    if (code != 200) {
      final message = plainText(asText(envelope['message']));
      throw ApiFailure(
        code,
        message.length > 500
            ? message.substring(0, 500)
            : message.isEmpty
            ? 'Request failed'
            : message,
      );
    }
    return envelope['data'];
  }

  Future<Uint8List> attachment(
    int id, {
    Future<void>? abort,
    void Function(int received, int? total)? progress,
  }) async {
    final r = await _send(
      'GET',
      '/mobile/attachments/$id',
      abort: abort,
      progress: progress,
      maxBytes: 10 * 1024 * 1024,
    );
    if (r.statusCode != 200) {
      throw ApiFailure(r.statusCode, 'Cannot download attachment');
    }
    if (r.headers['content-type']?.contains('application/json') == true) {
      throw const ApiFailure(502, 'Download was rejected by the server');
    }
    return r.bodyBytes;
  }

  void close() => _client.close();
}
