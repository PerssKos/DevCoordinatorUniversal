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
    'collection summaries do not expose internal fallback identifiers',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const containerSecret = 'sha256:internal-container-identity';
      const leaseSecret = 'internal-lease-identity';
      const repositorySecret = 'internal-repository-identity';
      const projectRootSecret = '/private/secret/project/root';
      const processSecret = 98765;
      final project = projectFixture(
        id: repositorySecret,
        root: projectRootSecret,
        displayName: 'Visible Project',
      );
      final inventory = emptyInventory(
        projects: <CoordinatorProject>[project],
        servers: <CoordinatorServer>[
          CoordinatorServer(
            id: 'internal-server-identity',
            repoId: repositorySecret,
            projectRoot: projectRootSecret,
            name: 'Visible Server',
            status: 'running',
            arguments: const <String>['serve'],
            pid: processSecret,
            port: 3211,
          ),
        ],
        containers: <CoordinatorContainer>[
          CoordinatorContainer(
            id: 'container-resource',
            containerId: containerSecret,
            name: 'Worker',
            status: 'running',
            ports: <CoordinatorPortBinding>[],
          ),
        ],
        leases: <CoordinatorLease>[
          const CoordinatorLease(
            id: leaseSecret,
            port: 3210,
            status: 'active',
            repoId: repositorySecret,
            projectRoot: projectRootSecret,
          ),
        ],
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
      controller.selectSection(AppSection.projects);

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('Visible Project'), findsOne);
      expect(find.text(projectRootSecret), findsNothing);
      expect(find.text(repositorySecret), findsNothing);

      controller.selectSection(AppSection.servers);
      await tester.pumpAndSettle();

      expect(find.text('Visible Server'), findsOne);
      expect(find.text('Visible Project'), findsOne);
      expect(find.text(projectRootSecret), findsNothing);
      expect(find.text('PID $processSecret'), findsNothing);

      controller.selectSection(AppSection.containers);
      await tester.pumpAndSettle();

      expect(find.text('Image unavailable'), findsOne);
      expect(find.text(containerSecret), findsNothing);

      controller.selectSection(AppSection.ports);
      await tester.pumpAndSettle();

      expect(find.text('Visible Project'), findsOne);
      expect(find.text(leaseSecret), findsNothing);
      expect(find.text(repositorySecret), findsNothing);
      expect(find.text(projectRootSecret), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unnamed project stays non-actionable instead of exposing its path',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const projectId = 'private-project-identity';
      const projectRoot = '/private/customer/phoenix';
      final controller = AppController(
        settingsStore: FakeSettingsStore(
          PersistedAppSettings(
            updateChecksEnabled: false,
            connection: localProfile(),
          ),
        ),
        tokenStore: FakeTokenStore(value: 't' * 40),
        coordinatorFactory: FakeCoordinatorServiceFactory(
          service: FakeCoordinatorService(
            inventory: emptyInventory(
              projects: <CoordinatorProject>[
                projectFixture(
                  id: projectId,
                  root: projectRoot,
                  displayName: '',
                ),
              ],
            ),
          ),
        ),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.selectSection(AppSection.projects);

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('Unnamed project'), findsOne);
      expect(find.text(projectId), findsNothing);
      expect(find.text(projectRoot), findsNothing);
      for (final label in <String>['Start', 'Restart', 'Stop']) {
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, label))
              .onPressed,
          isNull,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate visible targets use deterministic safe labels everywhere',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 1100)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const projectAId = 'private-project-a';
      const projectBId = 'private-project-b';
      const projectARoot = '/private/projects/a';
      const projectBRoot = '/private/projects/b';
      const serverAId = 'private-server-a';
      const serverBId = 'private-server-b';
      const containerAId =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const containerBId =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const leaseAId = 'private-lease-a';
      const leaseBId = 'private-lease-b';
      const processA = 41001;
      const processB = 41002;

      final projectA = projectFixture(
        id: projectAId,
        root: projectARoot,
        displayName: 'Shared Project',
      );
      final projectB = projectFixture(
        id: projectBId,
        root: projectBRoot,
        displayName: 'Shared Project',
      );
      final serverA = CoordinatorServer(
        id: serverAId,
        repoId: projectAId,
        projectRoot: projectARoot,
        name: 'Shared Server',
        status: 'running',
        arguments: const <String>['serve'],
        pid: processA,
        port: 3211,
      );
      final serverB = CoordinatorServer(
        id: serverBId,
        repoId: projectBId,
        projectRoot: projectBRoot,
        name: 'Shared Server',
        status: 'running',
        arguments: const <String>['serve'],
        pid: processB,
        port: 3212,
      );
      final containerA = CoordinatorContainer(
        id: 'normalized-container-a',
        containerId: containerAId,
        repoId: projectAId,
        projectRoot: projectARoot,
        name: 'Shared Container',
        status: 'running',
        ports: const <CoordinatorPortBinding>[],
      );
      final containerB = CoordinatorContainer(
        id: 'normalized-container-b',
        containerId: containerBId,
        repoId: projectBId,
        projectRoot: projectBRoot,
        name: 'Shared Container',
        status: 'running',
        ports: const <CoordinatorPortBinding>[],
      );
      const leaseA = CoordinatorLease(
        id: leaseAId,
        port: 3210,
        status: 'active',
        repoId: projectAId,
        projectRoot: projectARoot,
        purpose: 'Shared lease',
      );
      const leaseB = CoordinatorLease(
        id: leaseBId,
        port: 3210,
        status: 'active',
        repoId: projectBId,
        projectRoot: projectBRoot,
        purpose: 'Shared lease',
      );
      final service = FakeCoordinatorService(
        // Reverse source order proves the ordinals do not depend on card order.
        inventory: emptyInventory(
          projects: <CoordinatorProject>[projectB, projectA],
          servers: <CoordinatorServer>[serverB, serverA],
          containers: <CoordinatorContainer>[containerB, containerA],
          leases: const <CoordinatorLease>[leaseB, leaseA],
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
        coordinatorFactory: FakeCoordinatorServiceFactory(service: service),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.selectSection(AppSection.projects);

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('Shared Project · 1/2'), findsOne);
      expect(find.text('Shared Project · 2/2'), findsOne);
      await tester.tap(find.widgetWithText(AppButton, 'Stop').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Stop the exact target “Shared Project · 2/2”?'),
        findsOne,
      );
      _expectSecretsHidden(tester, <Object>[
        projectAId,
        projectBId,
        projectARoot,
        projectBRoot,
        serverAId,
        serverBId,
        containerAId,
        containerBId,
        leaseAId,
        leaseBId,
        processA,
        processB,
      ]);
      await tester.tap(find.widgetWithText(AppButton, 'Stop').last);
      await tester.pumpAndSettle();
      expect(controller.state.lastActionLabel, 'Stop Shared Project · 2/2');

      controller.selectSection(AppSection.servers);
      await tester.pumpAndSettle();

      expect(find.text('Shared Server · 1/2'), findsOne);
      expect(find.text('Shared Server · 2/2'), findsOne);
      expect(find.text('Shared Project · 1/2'), findsOne);
      expect(find.text('Shared Project · 2/2'), findsOne);
      await tester.tap(find.widgetWithText(AppButton, 'Logs').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Logs: Shared Server · 2/2 — Shared Project · 2/2'),
        findsOne,
      );
      _expectSecretsHidden(tester, <Object>[
        projectAId,
        projectBId,
        projectARoot,
        projectBRoot,
        serverAId,
        serverBId,
        processA,
        processB,
      ]);
      await tester.tap(find.widgetWithText(AppButton, 'Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Stop').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Stop the exact target “Shared Server · 2/2 — '
          'Shared Project · 2/2”?',
        ),
        findsOne,
      );
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();

      controller.selectSection(AppSection.containers);
      await tester.pumpAndSettle();

      expect(find.text('Shared Container · 1/2'), findsOne);
      expect(find.text('Shared Container · 2/2'), findsOne);
      expect(find.text('Shared Project · 1/2'), findsOne);
      expect(find.text('Shared Project · 2/2'), findsOne);
      await tester.tap(find.widgetWithText(AppButton, 'Logs').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Logs: Shared Container · 2/2 — Shared Project · 2/2'),
        findsOne,
      );
      _expectSecretsHidden(tester, <Object>[
        projectAId,
        projectBId,
        projectARoot,
        projectBRoot,
        containerAId,
        containerBId,
      ]);
      await tester.tap(find.widgetWithText(AppButton, 'Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Stop').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Stop the exact target “Shared Container · 2/2 — '
          'Shared Project · 2/2”?',
        ),
        findsOne,
      );
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();

      controller.selectSection(AppSection.ports);
      await tester.pumpAndSettle();

      expect(find.text('Shared lease · 1/2'), findsOne);
      expect(find.text('Shared lease · 2/2'), findsOne);
      await tester.tap(find.widgetWithText(AppButton, 'Release').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Release the exact target “3210 — Shared lease · 2/2 — '
          'Shared Project · 2/2”?',
        ),
        findsOne,
      );
      _expectSecretsHidden(tester, <Object>[
        projectAId,
        projectBId,
        projectARoot,
        projectBRoot,
        leaseAId,
        leaseBId,
      ]);
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(AppButton, 'Lease a port'));
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<CoordinatorProject>>(
        find.byType(DropdownButton<CoordinatorProject>),
      );
      final choiceLabels = dropdown.items!
          .map((item) => (item.child as Text).data)
          .toList(growable: false);
      expect(choiceLabels, <String?>[
        'Shared Project · 2/2',
        'Shared Project · 1/2',
      ]);
      _expectSecretsHidden(tester, <Object>[
        projectAId,
        projectBId,
        projectARoot,
        projectBRoot,
      ]);
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'container actions and logs require an immutable container identifier',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const projectId = 'private-project-identity';
      const projectRoot = '/private/container/project';
      const normalizedContainerId = 'private-normalized-container-identity';
      const unsafeShortContainerId = 'short-container-id';
      final project = projectFixture(id: projectId, root: projectRoot);
      final controller = AppController(
        settingsStore: FakeSettingsStore(
          PersistedAppSettings(
            updateChecksEnabled: false,
            connection: localProfile(),
          ),
        ),
        tokenStore: FakeTokenStore(value: 't' * 40),
        coordinatorFactory: FakeCoordinatorServiceFactory(
          service: FakeCoordinatorService(
            inventory: emptyInventory(
              projects: <CoordinatorProject>[project],
              containers: <CoordinatorContainer>[
                CoordinatorContainer(
                  id: normalizedContainerId,
                  containerId: unsafeShortContainerId,
                  repoId: projectId,
                  projectRoot: projectRoot,
                  name: 'Visible Container',
                  status: 'running',
                  ports: const <CoordinatorPortBinding>[],
                ),
              ],
            ),
          ),
        ),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.selectSection(AppSection.containers);

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      for (final label in <String>['Logs', 'Restart', 'Stop']) {
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, label))
              .onPressed,
          isNull,
        );
      }
      expect(
        find.textContaining(
          'full immutable Docker container identifier and exact project ownership',
        ),
        findsOne,
      );
      expect(
        find.textContaining(
          'Logs are blocked because a full immutable Docker container identifier',
        ),
        findsOne,
      );
      _expectSecretsHidden(tester, <Object>[
        projectId,
        projectRoot,
        normalizedContainerId,
        unsafeShortContainerId,
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectSecretsHidden(WidgetTester tester, Iterable<Object> secrets) {
  final renderedText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .join('\n');
  for (final secret in secrets) {
    expect(renderedText, isNot(contains('$secret')));
  }
}
