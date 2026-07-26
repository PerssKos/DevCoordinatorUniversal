import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'core/auth/native_authorization_router.dart';
import 'core/auth/native_session_store.dart';
import 'core/coordinator/legacy_coordinator_service.dart';
import 'core/storage/secure_token_store.dart';
import 'core/storage/settings_store.dart';
import 'core/update/repository_update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final callbackRouter = PlatformNativeAuthorizationCallbackRouter();
  await callbackRouter.initialize();
  final controller = AppController(
    settingsStore: PlatformAppSettingsStore(),
    tokenStore: PlatformSecureTokenStore(),
    coordinatorFactory: PlatformCoordinatorServiceFactory(
      nativeSessionStore: PlatformNativeSessionStore(),
      callbackRouter: callbackRouter,
      browserLauncher: const PlatformNativeSystemBrowserLauncher(),
    ),
    updateService: RepositoryAppUpdateService(),
  );

  runApp(DevCoordinatorApp(controller: controller));
  await controller.initialize();
}
