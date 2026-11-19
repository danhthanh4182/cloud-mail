import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'app_controller.dart';
import 'data/vault.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(DeviceVault());
  runApp(CloudMailApp(controller: controller));
  unawaited(controller.initialize());
}
