part of 'app_controller.dart';

extension DraftSync on AppController {
  Future<void> syncDrafts() async {
    if (!signedIn || !capabilities.draftSync || draftsSyncing) return;
    final client = api!, generation = _generation;
    draftsSyncing = true;
    draftSyncStatus = '';
    changed();
    try {
      final remote = <String, Map<String, dynamic>>{};
      String? cursor;
      var pages = 0;
      do {
        final data = await client.request(
          'GET',
          '/mobile/v2/drafts',
          query: {'cursor': ?cursor},
        ) as Map;
        _requireGeneration(generation);
        for (final item in decodeList(data['list']).whereType<Map>()) {
          remote[asText(item['draftId'])] = Map<String, dynamic>.from(item);
        }
        final next = data['nextCursor'] as String?;
        if (next != null &&
            (++pages >= 100 ||
                (cursor != null && next.compareTo(cursor) <= 0))) {
          throw const ApiFailure(502, 'Invalid or oversized draft listing');
        }
        cursor = next;
      } while (cursor != null);
      for (final entry in draftDeletes.entries.toList()) {
        final revision = entry.value == 0
            ? asInt(remote[entry.key]?['revision'])
            : entry.value;
        if (revision == 0) {
          draftDeletes.remove(entry.key);
          continue;
        }
        try {
          await client.request(
            'DELETE',
            '/mobile/v2/drafts/${entry.key}',
            query: {'revision': '$revision'},
          );
          _requireGeneration(generation);
          remote.remove(entry.key);
        } on ApiFailure catch (e) {
          _requireGeneration(generation);
          if (e.code != 409) rethrow;
          draftSyncStatus = t(
            'Bản nháp đã đổi trên máy khác. Giữ bản từ máy chủ.',
            'A draft changed on another device. The server copy was retained.',
          );
        }
        draftDeletes.remove(entry.key);
        await _persistDrafts();
        _requireGeneration(generation);
      }
      for (final draft in drafts.toList()) {
        final row = remote.remove(draft.id);
        if (draft.outcomeUncertain || draft.conflictCopy) continue;
        final revision = asInt(row?['revision']);
        if (row != null && revision != draft.revision) {
          if (draftChanged(draft)) {
            _preserveConflict(draft);
          } else {
            // Never discard private attachments while replacing a clean text replica.
            if (draft.attachments.isNotEmpty) {
              _preserveConflict(draft);
            } else {
              drafts.remove(draft);
            }
          }
          if (row['deleted'] != true) drafts.add(_remoteDraft(row));
          continue;
        }
        if (draftChanged(draft)) {
          final snapshot = draftReplica(draft);
          try {
            final response = await client.request(
              'PUT',
              '/mobile/v2/drafts/${draft.id}',
              body: {'revision': draft.revision, 'payload': snapshot},
            ) as Map;
            _requireGeneration(generation);
            draft.revision = asInt(response['revision']);
            if (draftDeletes.containsKey(draft.id)) {
              draftDeletes[draft.id] = draft.revision;
            } else {
              draft.syncStamp = jsonEncode(snapshot);
            }
            await _persistDrafts();
            _requireGeneration(generation);
          } on ApiFailure catch (e) {
            _requireGeneration(generation);
            if (e.code != 409) rethrow;
            // The change happened after listing. The next refresh pulls its copy.
            _preserveConflict(draft);
          }
        }
      }
      for (final row in remote.values) {
        if (row['deleted'] != true &&
            !draftDeletes.containsKey(asText(row['draftId'])) &&
            !drafts.any((draft) => draft.id == row['draftId'])) {
          drafts.add(_remoteDraft(row));
        }
      }
      await _persistDrafts();
      _requireGeneration(generation);
      draftLastSync = DateTime.now();
    } catch (e) {
      if (generation == _generation) draftSyncStatus = e.toString();
    } finally {
      if (generation == _generation) {
        draftsSyncing = false;
        changed();
      }
    }
  }

  MailDraft _remoteDraft(Map<String, dynamic> row) {
    final payload = Map<String, dynamic>.from(row['payload'] as Map);
    final draft = MailDraft.fromJson({
      ...payload,
      'id': row['draftId'],
      'revision': row['revision'],
      'missingAttachments': payload['attachmentCount'],
    });
    draft.syncStamp = draftStamp(draft);
    return draft;
  }

  void _preserveConflict(MailDraft draft) {
    final index = drafts.indexOf(draft);
    if (index < 0) return;
    drafts[index] = MailDraft.fromJson({
      ...draft.toJson(),
      'id': newId(),
      'revision': 0,
      'syncStamp': '',
      'conflictCopy': true,
    });
    draftSyncStatus = t(
      'Có xung đột. Bản chỉnh sửa trên máy này được giữ riêng.',
      'A conflict copy was kept on this device.',
    );
  }
}
