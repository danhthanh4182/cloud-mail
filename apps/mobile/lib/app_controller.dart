import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'data/api.dart';
import 'data/vault.dart';
import 'domain/mail.dart';
import 'domain/mail_sync.dart';

part 'draft_sync.dart';
part 'offline_edits.dart';
part 'push_session.dart';

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
  final Map<String, int> draftDeletes = {};
  List<PendingMailEdit> pendingEdits = [];
  bool draftsSyncing = false, editsSyncing = false;
  String draftSyncStatus = '';
  DateTime? draftLastSync, lastServerSync;
  bool pushConfigured = false, pushBusy = false;
  String? pushDevice;
  String pushStatus = '';
  bool get legacyStarred => folder == 'star' && !capabilities.organization;
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
  int _generation = 0, _loadTicket = 0, _pageCursor = 0;
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
        if (session['capabilities'] is Map) {
          capabilities = Capabilities.fromJson(
            Map<String, dynamic>.from(session['capabilities'] as Map),
          );
        }
        addresses = decodeList(session['addresses'])
            .map((x) => MailAddress.fromJson(Map<String, dynamic>.from(x)))
            .toList();
        await _restoreDrafts();
        await _restoreEdits();
        final cached = await vault.read(_cacheKey);
        if (cached != null) {
          _restoreMailboxCache(cached);
        }
        messages = _withEdits(messages);
        offline = true;
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
      _requireGeneration(generation);
      await _fetchCapabilities();
      _requireGeneration(generation);
      await _restoreDrafts();
      await _restoreEdits();
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

  void _requireGeneration(int generation) {
    if (_disposed || generation != _generation || !signedIn) {
      throw const ApiFailure(401, 'Session changed');
    }
  }

  Future<void> _fetchCapabilities() async {
    final client = api!, generation = _generation;
    try {
      final data = await client.request('GET', '/mobile/capabilities');
      _requireGeneration(generation);
      capabilities = data is Map
          ? Capabilities.fromJson(Map<String, dynamic>.from(data))
          : const Capabilities();
    } on ApiFailure catch (e) {
      _requireGeneration(generation);
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
        'capabilities': capabilities.toJson(),
        'addresses': addresses.map((a) => a.toJson()).toList(),
      }),
    );
  }

  Future<void> _restoreDrafts() async {
    final generation = _generation;
    final saved = await vault.read('drafts:$scope');
    _requireGeneration(generation);
    final data = saved == null ? null : jsonDecode(saved);
    drafts = decodeList(data is Map ? data['items'] : data)
        .whereType<Map>()
        .map((x) => MailDraft.fromJson(Map<String, dynamic>.from(x)))
        .toList();
    draftDeletes.clear();
    if (data is Map && data['deletes'] is Map) {
      for (final entry in (data['deletes'] as Map).entries) {
        draftDeletes['${entry.key}'] = asInt(entry.value);
      }
    }
  }

  Future<void> _persistDrafts() => _write(
    'drafts:$scope',
    jsonEncode({
      'items': drafts.map((draft) => draft.toJson()).toList(),
      'deletes': draftDeletes,
    }),
  );

  List<MailMessage> _withEdits(List<MailMessage> list) {
    final edits = {
      for (final edit in pendingEdits)
        if (!edit.conflict) edit.emailId: edit,
    };
    return list.map((row) => edits[row.id]?.apply(row) ?? row).where((row) {
      if (folder == 'star') return row.starred;
      if (folder == 'sent') return row.folder == 'inbox';
      return row.folder == folder;
    }).toList();
  }

  void _restoreMailboxCache(String encoded) {
    final cache = jsonDecode(encoded);
    if (cache is Map) {
      lastServerSync = DateTime.tryParse(asText(cache['syncedAt']));
    }
    messages = decodeList(cache is Map ? cache['messages'] : cache)
        .map((row) => MailMessage.fromJson(Map<String, dynamic>.from(row)))
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
          _restoreMailboxCache(cached);
          messages = _withEdits(messages);
          changed();
        } catch (_) {}
      }
    }
    try {
      if (!more) await _flushEdits();
      if (ticket != _loadTicket || generation != _generation) return;
      final cursor = more ? _pageCursor : 0;
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
              'accountId':
                  '${legacyStarred ? addresses.first.id : selectedAddress ?? addresses.first.id}',
              'allReceive': selectedAddress == null ? '1' : '0',
              'emailId': '$cursor',
              'timeSort': '0',
              'size': '25',
              'type': folder == 'sent' ? '1' : '0',
              'full': '1',
            };
      if (query.isNotEmpty && !legacyStarred) {
        params['text'] = query;
        params['searchType'] = searchType;
      }
      if (startDate.isNotEmpty && !legacyStarred) {
        params['startDate'] = startDate;
      }
      if (endDate.isNotEmpty && !legacyStarred) params['endDate'] = endDate;
      final response = await client.request('GET', path, query: params);
      if (ticket != _loadTicket || generation != _generation) return;
      final rows = response is Map ? decodeList(response['list']) : <dynamic>[];
      final page = rows
          .whereType<Map>()
          .map((x) => MailMessage.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      if (page.isNotEmpty) _pageCursor = page.last.id;
      lastServerSync = DateTime.now();
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
      messages = _withEdits(messages);
      await _write(
        key,
        jsonEncode({
          'messages': cached,
          'syncedAt': lastServerSync?.toIso8601String(),
        }),
      );
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
    if (['archive', 'spam', 'trash'].contains(value) &&
        !capabilities.organization) {
      throw const ApiFailure(503, 'The server needs the mobile API update');
    }
    folder = value;
    if (legacyStarred) selectedAddress = null;
    messages = [];
    hasMore = false;
    query = '';
    error = '';
    ++_loadTicket;
    changed();
    if (value == 'drafts') {
      await syncDrafts();
    } else {
      await loadMessages();
    }
  }

  Future<void> selectAddress(int? id) async {
    if (legacyStarred) return;
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
          final row = Map<String, dynamic>.from(data as Map);
          current = MailMessage.fromJson(row).copy(
            starred: row.containsKey('isStar') ? null : mail.starred,
            version: row.containsKey('version') ? null : mail.version,
            folder: row.containsKey('folder') ? null : mail.folder,
            labels: row.containsKey('labels') ? null : mail.labels,
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
        _requireGeneration(generation);
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
    final patch = <String, dynamic>{
      'version': mail.version,
      'folder': ?target,
      'labels': ?labels,
      'read': ?read,
    };
    if (offline || pendingEdits.any((edit) => edit.emailId == mail.id)) {
      return _queueEdit(mail, patch);
    }
    Object? response;
    try {
      response = await client.request(
        'PUT',
        '/mobile/mail/${mail.id}/state',
        body: patch,
      );
    } on ApiFailure catch (e) {
      _requireGeneration(generation);
      if (e.code != 0) rethrow;
      offline = true;
      return _queueEdit(mail, patch);
    }
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

  Future<({List<MailMessage> list, bool truncated})> conversation(
    MailMessage mail,
  ) async {
    final generation = _generation;
    final result = await api!.request(
      'GET',
      '/mobile/mail/${mail.id}/conversation',
    ) as Map;
    _requireGeneration(generation);
    final list = decodeList(result['list'])
        .whereType<Map>()
        .map((row) => MailMessage.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return (list: list, truncated: result['truncated'] == true);
  }

  Future<void> setSenderCategory(String sender, String category) async {
    final generation = _generation;
    if (category.isEmpty) {
      await api!.request(
        'DELETE',
        '/mobile/rules/sender',
        query: {'sender': sender},
      );
    } else {
      await api!.request(
        'PUT',
        '/mobile/rules/sender',
        body: {'sender': sender, 'category': category},
      );
    }
    _requireGeneration(generation);
    await loadMessages();
  }

  Future<String> suggestReply(MailMessage mail) async {
    final generation = _generation;
    final row = await api!.request(
      'POST',
      '/mobile/assistant/${mail.id}',
      query: {'mode': 'reply'},
    ) as Map;
    _requireGeneration(generation);
    return asText(row['draft']);
  }

  Future<void> saveDraft(MailDraft draft) async {
    final index = drafts.indexWhere((d) => d.id == draft.id);
    if (index < 0) {
      drafts.insert(0, draft);
    } else {
      drafts[index] = draft;
    }
    await _persistDrafts();
    changed();
  }

  Future<void> deleteDraft(MailDraft draft) async {
    if (draft.revision > 0 || draftsSyncing) {
      draftDeletes[draft.id] = draft.revision;
    }
    drafts.removeWhere((d) => d.id == draft.id);
    await _persistDrafts();
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
    if (draft.missingAttachments > 0) {
      throw const ApiFailure(409, 'Attachments are on the original device');
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
    if (draft.requestKey.isEmpty) {
      draft.requestKey = draft.revision > 0
          ? sha256
                .convert(utf8.encode('draft:${draft.id}:${draft.revision}'))
                .toString()
          : newId();
    }
    draft.sendState = 'pending';
    final client = api!, generation = _generation;
    await saveDraft(draft);
    _requireGeneration(generation);
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
      draft.sendState = switch (e) {
        ApiFailure(code: 409) => 'conflict',
        ApiFailure(code: 400 || 403 || 413) => 'rejected',
        _ => 'unknown',
      };
      if (generation == _generation) await saveDraft(draft);
      rethrow;
    }
  }

  Future<String> retryMissingIntent(MailDraft draft) async {
    if (draft.sendState != 'notSubmitted') {
      throw const ApiFailure(409, 'Reconcile the send first');
    }
    draft.sendState = '';
    return sendDraft(draft);
  }

  Future<String> reconcile(MailDraft draft) async {
    final client = api!, generation = _generation;
    Object? data;
    try {
      data = await client.request(
        'GET',
        '/mobile/send/${draft.requestKey}',
        query: {'payloadHash': sendPayloadHash(draft.sendPayload())},
      );
    } on ApiFailure catch (e) {
      _requireGeneration(generation);
      if (e.code == 409) {
        draft.sendState = 'conflict';
        await saveDraft(draft);
        rethrow;
      }
      if (e.code != 404) rethrow;
      draft.sendState = 'notSubmitted';
      await saveDraft(draft);
      return draft.sendState;
    }
    _requireGeneration(generation);
    draft.sendState = asText((data as Map)['state']);
    if (draft.sendState == 'accepted') {
      await deleteDraft(draft);
    } else {
      await saveDraft(draft);
    }
    return draft.sendState;
  }

  Future<Map<String, dynamic>> summarize(MailMessage mail) async {
    final client = api!, generation = _generation;
    final result = await client.request('POST', '/mobile/assistant/${mail.id}');
    _requireGeneration(generation);
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
    final pushKey = 'push:$scope', pushRotationKey = 'push-rotation:$scope';
    final device = pushDevice;
    final hadPush =
        capabilities.push || pushConfigured || device != null || pushBusy;
    ++_generation;
    ++_loadTicket;
    api = null;
    profile = {};
    addresses = [];
    messages = [];
    drafts = [];
    draftDeletes.clear();
    pendingEdits = [];
    draftsSyncing = false;
    editsSyncing = false;
    draftSyncStatus = '';
    draftLastSync = null;
    lastServerSync = null;
    pushConfigured = false;
    pushBusy = false;
    pushDevice = null;
    pushStatus = '';
    capabilities = const Capabilities();
    busy = false;
    ready = true;
    loading = false;
    offline = false;
    error = '';
    final removal = _writes
        .catchError((_) {})
        .then((_) => vault.delete('session'));
    _writes = removal;
    if (hadPush) {
      try {
        await pushChannel
            .invokeMethod<void>('disable')
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      await vault.delete(pushKey);
      await vault.delete(pushRotationKey);
    }
    await removal;
    changed();
    if (client != null) {
      try {
        if (device != null) {
          try {
            await client
                .request('DELETE', '/mobile/devices/$device')
                .timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
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
