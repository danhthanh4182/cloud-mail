part of 'app_controller.dart';

extension OfflineEdits on AppController {
  Future<void> _restoreEdits() async {
    final generation = _generation;
    final value = await vault.read('edits:$scope');
    _requireGeneration(generation);
    pendingEdits = value == null
        ? []
        : decodeList(jsonDecode(value))
              .whereType<Map>()
              .map(
                (item) =>
                    PendingMailEdit.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList();
  }

  Future<void> _persistEdits() => _write(
    'edits:$scope',
    jsonEncode(pendingEdits.map((edit) => edit.toJson()).toList()),
  );

  Future<MailMessage> _queueEdit(
    MailMessage mail,
    Map<String, dynamic> patch,
  ) async {
    if (pendingEdits.length >= 100) {
      throw const ApiFailure(409, 'Sync pending changes before adding more');
    }
    final existing = pendingEdits.indexWhere((item) => item.emailId == mail.id);
    if (existing >= 0 && pendingEdits[existing].conflict) {
      throw const ApiFailure(
        409,
        'Resolve the pending conflict before editing',
      );
    }
    if (existing >= 0 && editsSyncing) {
      throw const ApiFailure(409, 'Wait for the active sync to finish');
    }
    final edit = PendingMailEdit(mail.id, {
      if (existing >= 0) ...pendingEdits[existing].patch,
      ...patch,
      'version': existing >= 0
          ? pendingEdits[existing].patch['version']
          : mail.version,
    });
    if (existing >= 0) {
      pendingEdits[existing] = edit;
    } else {
      pendingEdits.add(edit);
    }
    final generation = _generation;
    await _persistEdits();
    _requireGeneration(generation);
    final next = edit.apply(mail);
    _replace(next);
    return next;
  }

  Future<void> _flushEdits() async {
    if (editsSyncing || pendingEdits.isEmpty || !capabilities.organization) {
      return;
    }
    final client = api!, generation = _generation;
    editsSyncing = true;
    try {
      for (final edit in pendingEdits.toList()) {
        if (edit.conflict) continue;
        try {
          await client.request(
            'PUT',
            '/mobile/mail/${edit.emailId}/state',
            body: edit.patch,
          );
          _requireGeneration(generation);
          pendingEdits.remove(edit);
        } on ApiFailure catch (e) {
          _requireGeneration(generation);
          if (![404, 409].contains(e.code)) rethrow;
          final index = pendingEdits.indexOf(edit);
          if (index >= 0) {
            pendingEdits[index] = PendingMailEdit(
              edit.emailId,
              edit.patch,
              conflict: true,
            );
          }
        }
        await _persistEdits();
        _requireGeneration(generation);
      }
    } finally {
      if (generation == _generation) {
        editsSyncing = false;
        changed();
      }
    }
  }

  Future<void> discardEdits() async {
    if (!signedIn || editsSyncing) return;
    pendingEdits.clear();
    await _persistEdits();
    messages = [];
    await loadMessages();
  }
}
