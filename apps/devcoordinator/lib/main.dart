import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'core/coordinator/legacy_coordinator_service.dart';
import 'core/storage/secure_token_store.dart';
import 'core/storage/settings_store.dart';
import 'core/update/repository_update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController(
    settingsStore: PlatformAppSettingsStore(),
    tokenStore: PlatformSecureTokenStore(),
    coordinatorFactory: PlatformCoordinatorServiceFactory(),
    updateService: RepositoryAppUpdateService(),
  );

  runApp(DevCoordinatorApp(controller: controller));
  await controller.initialize();
}
