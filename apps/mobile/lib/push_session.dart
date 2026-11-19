part of 'app_controller.dart';

const pushChannel = MethodChannel('cloud_mail/push');

extension PushSession on AppController {
  Future<void> refreshPush() async {
    if (!signedIn || pushBusy) return;
    final generation = _generation;
    try {
      final configured =
          capabilities.push &&
          (await pushChannel.invokeMethod<bool>('configured') ?? false);
      _requireGeneration(generation);
      pushConfigured = configured;
      final stored = await vault.read('push:$scope');
      _requireGeneration(generation);
      if (stored != null && pushConfigured) {
        pushDevice = stored;
        final permitted =
            await pushChannel.invokeMethod<bool>('permission') ?? false;
        _requireGeneration(generation);
        if (!permitted) {
          await disablePush();
          return;
        }
        await _registerPush(stored);
      }
    } on MissingPluginException {
      if (generation == _generation) pushConfigured = false;
    } catch (e) {
      if (generation == _generation) pushStatus = e.toString();
    } finally {
      if (generation == _generation) changed();
    }
  }

  Future<void> enablePush() async {
    if (!signedIn || !pushConfigured || pushBusy) return;
    final generation = _generation;
    pushBusy = true;
    changed();
    try {
      final permitted =
          await pushChannel.invokeMethod<bool>('requestPermission') ?? false;
      _requireGeneration(generation);
      if (!permitted) {
        pushStatus = t(
          'Android chưa cấp quyền thông báo.',
          'Android notification permission is denied.',
        );
        return;
      }
      await _registerPush(pushDevice ?? newId());
    } finally {
      if (generation == _generation) {
        pushBusy = false;
        changed();
      }
    }
  }

  Future<void> _registerPush(String device) async {
    final generation = _generation,
        client = api!,
        key = 'push:$scope',
        rotationKey = 'push-rotation:$scope';
    pushBusy = true;
    changed();
    try {
      final rotation = await vault.read(rotationKey) ?? '${newId()}${newId()}';
      _requireGeneration(generation);
      final token = await pushChannel.invokeMethod<String>('token');
      _requireGeneration(generation);
      await client.request(
        'PUT',
        '/mobile/devices/$device',
        body: {'token': token, 'rotationKey': rotation},
      );
      _requireGeneration(generation);
      await _write(rotationKey, rotation);
      _requireGeneration(generation);
      await _write(key, device);
      _requireGeneration(generation);
      await pushChannel.invokeMethod<void>('enable', {
        'device': device,
        'language': language,
        'origin': client.origin.toString(),
        'rotation': rotation,
      });
      _requireGeneration(generation);
      pushDevice = device;
      pushStatus = '';
    } finally {
      if (generation == _generation) {
        pushBusy = false;
        changed();
      }
    }
  }

  Future<void> disablePush() async {
    if (!signedIn) return;
    final client = api!,
        device = pushDevice,
        key = 'push:$scope',
        rotationKey = 'push-rotation:$scope';
    pushDevice = null;
    pushStatus = '';
    changed();
    await pushChannel
        .invokeMethod<void>('disable')
        .timeout(const Duration(seconds: 5));
    await vault.delete(key);
    await vault.delete(rotationKey);
    if (device != null) {
      await client.request('DELETE', '/mobile/devices/$device');
    }
  }

  Future<MailMessage?> takeNotification() async {
    if (!signedIn || pushDevice == null || !capabilities.push) return null;
    final generation = _generation, client = api!;
    final intent = await pushChannel.invokeMapMethod<String, dynamic>(
      'takeIntent',
    );
    _requireGeneration(generation);
    final id = asInt(intent?['id']);
    if (id <= 0 || intent?['device'] != pushDevice) return null;
    final result = await client.request('GET', '/mobile/mail/$id') as Map;
    _requireGeneration(generation);
    return MailMessage.fromJson(Map<String, dynamic>.from(result));
  }
}
