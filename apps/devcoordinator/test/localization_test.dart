import 'package:devcoordinator/app/app.dart';
import 'package:devcoordinator/app/app_controller.dart';
import 'package:devcoordinator/core/storage/settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Russian system locale selects the Russian application copy', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale('ru'),
    ];
    try {
      final controller = AppController(
        settingsStore: FakeSettingsStore(
          const PersistedAppSettings(updateChecksEnabled: false),
        ),
        tokenStore: FakeTokenStore(),
        coordinatorFactory: FakeCoordinatorServiceFactory(
          service: FakeCoordinatorService(),
        ),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('Подключение'), findsOne);
      expect(find.text('Удалённый шлюз'), findsOne);
      expect(
        find.textContaining('Android и удалённые клиенты требуют'),
        findsOne,
      );
      expect(find.text('Подключиться'), findsOne);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.platformDispatcher.clearLocalesTestValue();
    }
  });
}
