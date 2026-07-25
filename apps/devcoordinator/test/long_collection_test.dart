import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator/app/app.dart';
import 'package:devcoordinator/app/app_controller.dart';
import 'package:devcoordinator/app/app_state.dart';
import 'package:devcoordinator/core/storage/settings_store.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a long compact lease collection keeps its creation action visible',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = projectFixture();
      final inventory = emptyInventory(
        projects: <CoordinatorProject>[project],
        servers: <CoordinatorServer>[
          enrolledServerFixture(
            repoId: project.id,
            projectRoot: project.canonicalRoot,
          ),
        ],
        leases: List<CoordinatorLease>.generate(
          60,
          (index) => CoordinatorLease(
            id: 'lease-$index',
            repoId: project.id,
            projectRoot: project.canonicalRoot,
            port: 3000 + index,
            status: 'active',
            purpose: 'Service ${index + 1}',
          ),
        ),
      );
      final controller = AppController(
        settingsStore: FakeSettingsStore(
          PersistedAppSettings(
            updateChecksEnabled: false,
            connection: localProfile(),
          ),
        ),
        tokenStore: FakeTokenStore(value: 't' * 40),
        coordinatorFactory: FakeCoordinatorServiceFactory(
          service: FakeCoordinatorService(inventory: inventory),
        ),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.selectSection(AppSection.ports);

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      final create = find.widgetWithText(AppButton, 'Lease a port');
      expect(find.text('60 visible leases'), findsOne);
      expect(create, findsOne);
      expect(tester.getCenter(create).dy, lessThan(844));

      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOne);
      expect(find.text('Allowed range'), findsOne);
      expect(tester.binding.focusManager.primaryFocus, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
