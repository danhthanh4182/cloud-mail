import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'data/api.dart';
import 'data/vault.dart';
import 'domain/mail.dart';

typedef ApiFactory = ApiClient Function(
  Uri origin,
  String token,
  String language,
);

class AppController extends ChangeNotifier {
  final Vault vault;
  final ApiFactory _factory;
  ApiClient? api;
  Map<String, dynamic> profile = {};
  List<MailAddress> addresses = [];
  List<MailMessage> messages = [];
  List<MailDraft> drafts = [];
  Capabilities capabilities = const Capabilities();
  bool ready = false,
      busy = false,
      loading = false,
      offline = false,
      hasMore = false;
  String error = '',
      folder = 'inbox',
      query = '',
      searchType = 'subject',
      startDate = '',
      endDate = '',
      language = 'vi',
      theme = 'system';
  int? selectedAddress;
  int _generation = 0, _loadTicket = 0;
  bool _disposed = false;
  Future<void> _writes = Future.value();
  AppController(this.vault, {ApiFactory? apiFactory})
    : _factory =
          apiFactory ??
          ((origin, token, language) =>
              ApiClient(origin, token: token, language: language));
  bool get signedIn => api != null && profile.isNotEmpty;
  String get scope => sha256
      .convert(utf8.encode('${api?.origin}|${profile['userId']}'))
      .toString();
  String t(String vi, String en) => language == 'vi' ? vi : en;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _write(String key, String value) {
    final work = _writes
        .catchError((_) {})
        .then((_) => vault.write(key, value));
    _writes = work;
    return work;
  }

  Future<void> initialize() async {
    try {
      final prefs = await vault.read('preferences');
      if (prefs != null) {
        final p = jsonDecode(prefs);
        language = p['language'] ?? 'vi';
        theme = p['theme'] ?? 'system';
      }
      final saved = await vault.read('session');
      if (saved != null) {
        final session = jsonDecode(saved) as Map<String, dynamic>;
        api = _factory(
          validateServer(session['origin']),
          session['token'],
          language,
        );
        profile = Map<String, dynamic>.from(session['profile']);
        addresses = decodeList(session['addresses'])
            .map((x) => MailAddress.fromJson(Map<String, dynamic>.from(x)))
            .toList();
        await _restoreDrafts();
        await loadMessages();
        final generation = _generation;
        try {
          final actual = await api!.request('GET', '/my/loginUserInfo');
          if (generation != _generation) return;
          if (actual is! Map ||
              asInt(actual['userId']) != asInt(profile['userId'])) {
            await logout();
            return;
          }
          profile = Map<String, dynamic>.from(actual);
          await _fetchCapabilities();
          await _fetchAddresses();
          await _saveSession();
          await loadMessages();
        } on ApiFailure catch (e) {
          if (e.code == 401) {
            await logout();
          } else {
            offline = true;
            error = e.message;
          }
        }
      }
    } catch (_) {
      error = t(
        'Không thể khôi phục phiên. Hãy đăng nhập lại.',
        'Cannot restore the session. Please sign in again.',
      );
      api?.close();
      api = null;
      profile = {};
    }
    ready = true;
    changed();
  }

  Future<void> login(String server, String email, String password) async {
    final origin = validateServer(server);
    final generation = ++_generation;
    busy = true;
    error = '';
    changed();
    final candidate = _factory(origin, '', language);
    try {
      final login = await candidate.request(
        'POST',
        '/login',
        body: {'email': email.trim(), 'password': password},
      );
      if (generation != _generation) {
        candidate.close();
        return;
      }
      if (login is! Map || asText(login['token']).isEmpty) {
        throw const ApiFailure(502, 'Invalid login response');
      }
      candidate.token = login['token'];
      final info = await candidate.request('GET', '/my/loginUserInfo');
      if (generation != _generation) {
        candidate.close();
        return;
      }
      if (info is! Map || asInt(info['userId']) <= 0) {
        throw const ApiFailure(502, 'Invalid profile response');
      }
      api?.close();
      api = candidate;
      profile = Map<String, dynamic>.from(info);
      messages = [];
      addresses = [];
      drafts = [];
      folder = 'inbox';
      selectedAddress = null;
      await _fetchAddresses();
      await _fetchCapabilities();
      await _restoreDrafts();
      if (generation != _generation) return;
      await _saveSession();
      await loadMessages();
    } catch (e) {
      if (generation == _generation) {
        candidate.close();
        api = null;
        profile = {};
        error = e.toString();
        rethrow;
      }
    } finally {
      if (generation == _generation) {
        busy = false;
        ready = true;
        changed();
      }
    }
  }

  Future<void> _fetchCapabilities() async {
    try {
      final data = await api!.request('GET', '/mobile/capabilities');
      capabilities = data is Map
          ? Capabilities.fromJson(Map<String, dynamic>.from(data))
          : const Capabilities();
    } on ApiFailure catch (e) {
      if (e.code != 404) rethrow;
      capabilities = const Capabilities();
    }
  }

  Future<void> _fetchAddresses() async {
    final client = api!, generation = _generation;
    final list = <MailAddress>[];
    int lastId = 0;
    int? lastSort;
    for (var page = 0; page < 20; page++) {
      final data = await client.request(
        'GET',
        '/account/list',
        query: {
          'accountId': '$lastId',
          'size': '30',
          if (lastSort != null) 'lastSort': '$lastSort',
        },
      );
      if (generation != _generation) return;
      final part = decodeList(data)
          .whereType<Map>()
          .map((x) => MailAddress.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      list.addAll(part);
      if (part.length < 30) break;
      lastId = part.last.id;
      lastSort = part.last.sort;
    }
    addresses = list;
  }

  Future<void> _saveSession() async {
    if (!signedIn) return;
    await _write(
      'session',
      jsonEncode({
        'origin': api!.origin.toString(),
        'token': api!.token,
        'profile': profile,
        'addresses': addresses.map((a) => a.toJson()).toList(),
      }),
    );
  }

  Future<void> _restoreDrafts() async {
    final saved = await vault.read('drafts:$scope');
    drafts = saved == null
        ? []
        : decodeList(jsonDecode(saved))
              .whereType<Map>()
              .map((x) => MailDraft.fromJson(Map<String, dynamic>.from(x)))
              .toList();
  }

  String get _cacheKey =>
      'mail:$scope:${sha256.convert(utf8.encode('$folder|$selectedAddress|$query|$searchType|$startDate|$endDate'))}';
  Future<void> loadMessages({bool more = false}) async {
    if (!signedIn ||
        addresses.isEmpty ||
        ['drafts', 'settings'].contains(folder)) {
      return;
    }
    final ticket = ++_loadTicket,
        generation = _generation,
        client = api!,
        key = _cacheKey;
    loading = true;
    error = '';
    changed();
    if (!more && messages.isEmpty) {
      final cached = await vault.read(key);
      if (ticket != _loadTicket || generation != _generation) return;
      if (cached != null) {
        try {
          messages = decodeList(jsonDecode(cached))
              .map((x) => MailMessage.fromJson(Map<String, dynamic>.from(x)))
              .toList();
          changed();
        } catch (_) {}
      }
    }
    try {
      final cursor = more && messages.isNotEmpty ? messages.last.id : 0;
      final path = capabilities.organization
          ? '/mobile/mail'
          : folder == 'star'
          ? '/star/list'
          : '/email/list';
      final params = capabilities.organization
          ? {
              'folder': folder,
              'type': folder == 'sent' ? 'sent' : 'receive',
              'cursor': '$cursor',
              'size': '25',
              if (selectedAddress != null) 'accountId': '$selectedAddress',
            }
          : {
              'accountId': '${selectedAddress ?? addresses.first.id}',
              'allReceive': selectedAddress == null ? '1' : '0',
              'emailId': '$cursor',
              'timeSort': '0',
              'size': '25',
              'type': folder == 'sent' ? '1' : '0',
              'full': '1',
            };
      if (query.isNotEmpty) {
        params['text'] = query;
        params['searchType'] = searchType;
      }
      if (startDate.isNotEmpty) params['startDate'] = startDate;
      if (endDate.isNotEmpty) params['endDate'] = endDate;
      final response = await client.request('GET', path, query: params);
      if (ticket != _loadTicket || generation != _generation) return;
      final rows = response is Map ? decodeList(response['list']) : <dynamic>[];
      final page = rows
          .whereType<Map>()
          .map((x) => MailMessage.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      messages = more
          ? {
              for (final m in [...messages, ...page]) m.id: m,
            }.values.toList()
          : page;
      hasMore = response is Map && response['hasMore'] is bool
          ? response['hasMore']
          : page.length == 25;
      offline = false;
      final cached = messages.take(50).map((m) {
        final j = m.toJson();
        for (final field in ['text', 'content']) {
          final value = j[field] as String;
          if (value.length > 32768) j[field] = value.substring(0, 32768);
        }
        return j;
      }).toList();
      await _write(key, jsonEncode(cached));
    } catch (e) {
      if (ticket == _loadTicket && generation == _generation) {
        offline = true;
        error = e.toString();
        if (e is ApiFailure && e.code == 401) await logout();
      }
    } finally {
      if (ticket == _loadTicket && generation == _generation) {
        loading = false;
        changed();
      }
    }
  }

  Future<void> selectFolder(String value) async {
    folder = value;
    messages = [];
    hasMore = false;
    query = '';
    error = '';
    ++_loadTicket;
    changed();
    await loadMessages();
  }

  Future<void> selectAddress(int? id) async {
    selectedAddress = id;
    messages = [];
    ++_loadTicket;
    changed();
    await loadMessages();
  }

  Future<MailMessage> open(MailMessage mail) async {
    final generation = _generation, client = api!;
    MailMessage current = mail;
    if (!offline) {
      try {
        if (capabilities.organization) {
          final data = await client.request('GET', '/mobile/mail/${mail.id}');
          current = MailMessage.fromJson(Map<String, dynamic>.from(data as Map))
              .copy(
                starred: mail.starred,
                version: mail.version,
                folder: mail.folder,
                labels: mail.labels,
              );
        } else {
          final atts = await client.request(
            'GET',
            '/email/attList',
            query: {'emailId': '${mail.id}'},
          );
          current = MailMessage.fromJson({...mail.toJson(), 'attList': atts});
        }
        if (generation != _generation) {
          throw const ApiFailure(401, 'Session changed');
        }
        await client.request(
          'PUT',
          '/email/read',
          body: {
            'emailIds': [mail.id],
          },
        );
        current = current.copy(unread: false);
        _replace(current);
      } on ApiFailure catch (e) {
        if (e.code == 401) rethrow;
        error = e.message;
      }
    }
    return current;
  }

  void _replace(MailMessage mail) {
    messages = messages.map((m) => m.id == mail.id ? mail : m).toList();
    changed();
  }

  Future<void> toggleStar(MailMessage mail) async {
    final client = api!, generation = _generation;
    await client.request(
      mail.starred ? 'DELETE' : 'POST',
      mail.starred ? '/star/cancel' : '/star/add',
      query: mail.starred ? {'emailId': '${mail.id}'} : null,
      body: mail.starred ? null : {'emailId': mail.id},
    );
    if (generation == _generation) _replace(mail.copy(starred: !mail.starred));
  }

  Future<MailMessage> organize(
    MailMessage mail, {
    String? target,
    List<String>? labels,
    bool? read,
  }) async {
    if (!capabilities.organization) {
      throw ApiFailure(
        503,
        t(
          'Máy chủ cần cập nhật API mobile.',
          'The server needs the mobile API update.',
        ),
      );
    }
    final client = api!, generation = _generation;
    final response = await client.request(
      'PUT',
      '/mobile/mail/${mail.id}/state',
      body: {
        'version': mail.version,
        'folder': ?target,
        'labels': ?labels,
        'read': ?read,
      },
    );
    if (generation != _generation) {
      throw const ApiFailure(401, 'Session changed');
    }
    final next = mail.copy(
      folder: target,
      labels: labels,
      unread: read == null ? null : !read,
      version: asInt((response as Map)['version']),
    );
    _replace(next);
    return next;
  }

  Future<void> saveDraft(MailDraft draft) async {
    final key = 'drafts:$scope';
    final index = drafts.indexWhere((d) => d.id == draft.id);
    if (index < 0) {
      drafts.insert(0, draft);
    } else {
      drafts[index] = draft;
    }
    await _write(key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
    changed();
  }

  Future<void> deleteDraft(MailDraft draft) async {
    drafts.removeWhere((d) => d.id == draft.id);
    await _write(
      'drafts:$scope',
      jsonEncode(drafts.map((d) => d.toJson()).toList()),
    );
    changed();
  }

  Future<String> sendDraft(MailDraft draft) async {
    if (!capabilities.safeSend) {
      throw ApiFailure(
        503,
        t(
          'Cập nhật Worker và migration mobile trước khi gửi an toàn. Bản nháp vẫn được giữ.',
          'Update the Worker and mobile migration before safe sending. Your draft is retained.',
        ),
      );
    }
    if (draft.outcomeUncertain) {
      throw ApiFailure(
        409,
        t(
          'Cần kiểm tra trạng thái lần gửi trước.',
          'Reconcile the previous send first.',
        ),
      );
    }
    final payload = draft.sendPayload();
    if ((payload['receiveEmail'] as List).isEmpty) {
      throw const FormatException('Recipient is required');
    }
    if (draft.requestKey.isEmpty) draft.requestKey = newId();
    draft.sendState = 'pending';
    await saveDraft(draft);
    final client = api!, generation = _generation;
    try {
      final response = await client.request(
        'POST',
        '/mobile/send',
        body: payload,
        headers: {'Idempotency-Key': draft.requestKey},
      );
      if (generation != _generation) {
        throw const ApiFailure(401, 'Session changed');
      }
      draft.sendState = asText((response as Map)['state']);
      if (draft.sendState == 'accepted') {
        await deleteDraft(draft);
      } else {
        await saveDraft(draft);
      }
      return draft.sendState;
    } catch (e) {
      draft.sendState = e is ApiFailure && [400, 403, 413].contains(e.code)
          ? 'rejected'
          : 'unknown';
      if (generation == _generation) await saveDraft(draft);
      rethrow;
    }
  }

  Future<String> reconcile(MailDraft draft) async {
    final data = await api!.request('GET', '/mobile/send/${draft.requestKey}');
    draft.sendState = asText((data as Map)['state']);
    if (draft.sendState == 'accepted') {
      await deleteDraft(draft);
    } else {
      await saveDraft(draft);
    }
    return draft.sendState;
  }

  Future<Map<String, dynamic>> summarize(MailMessage mail) async {
    final result = await api!.request('POST', '/mobile/assistant/${mail.id}');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> updatePreferences({String? language, String? theme}) async {
    this.language = language ?? this.language;
    this.theme = theme ?? this.theme;
    api?.language = this.language;
    await _write(
      'preferences',
      jsonEncode({'language': this.language, 'theme': this.theme}),
    );
    changed();
  }

  Future<void> refreshAddresses() async {
    await _fetchAddresses();
    await _saveSession();
    changed();
  }

  Future<void> logout() async {
    final client = api;
    ++_generation;
    ++_loadTicket;
    api = null;
    profile = {};
    addresses = [];
    messages = [];
    drafts = [];
    capabilities = const Capabilities();
    busy = false;
    loading = false;
    offline = false;
    error = '';
    final removal = _writes
        .catchError((_) {})
        .then((_) => vault.delete('session'));
    _writes = removal;
    await removal;
    changed();
    if (client != null) {
      try {
        await client
            .request('DELETE', '/logout')
            .timeout(const Duration(seconds: 5));
      } catch (_) {
      } finally {
        client.close();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    api?.close();
    super.dispose();
  }
}
