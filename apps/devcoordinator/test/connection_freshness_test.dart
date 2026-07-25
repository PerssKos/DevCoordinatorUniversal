import 'dart:async';

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

  test(
    'failed refresh retains a read-only snapshot after its banner is dismissed',
    () async {
      final project = projectFixture();
      final server = _serverFixture();
      final container = _containerFixture();
      final lease = leaseFixture();
      final inventory = emptyInventory(
        projects: <CoordinatorProject>[project],
        servers: <CoordinatorServer>[server],
        containers: <CoordinatorContainer>[container],
        leases: <CoordinatorLease>[lease],
      );
      final service = FakeCoordinatorService(inventory: inventory);
      final controller = await _connectedController(service);
      addTearDown(controller.dispose);

      expect(controller.state.availability, ConnectionAvailability.available);
      expect(controller.state.canMutate, isTrue);

      service.inventoryError = StateError('inventory offline');
      await controller.refresh();

      expect(controller.state.inventory, same(inventory));
      expect(controller.state.availability, ConnectionAvailability.stale);
      expect(controller.state.isConnected, isFalse);
      expect(controller.state.canMutate, isFalse);
      expect(controller.state.connectionError, contains('inventory offline'));

      controller.clearMessage();

      expect(controller.state.connectionError, isNull);
      expect(controller.state.availability, ConnectionAvailability.stale);
      expect(controller.state.canMutate, isFalse);

      await controller.runServerAction(server, CoordinatorResourceAction.stop);
      await controller.runProjectAction(project, CoordinatorProjectAction.stop);
      await controller.runContainerAction(
        container,
        CoordinatorResourceAction.stop,
      );
      expect(await controller.readServerLogs(server), isNull);
      expect(await controller.readContainerLogs(container), isNull);
      expect(
        await controller.leasePort(
          project: project,
          server: server,
          firstPort: 3000,
          lastPort: 3999,
        ),
        isNull,
      );
      await controller.releasePort(lease);

      expect(service.serverActions, isEmpty);
      expect(service.projectActions, isEmpty);
      expect(service.containerActions, isEmpty);
      expect(service.serverLogCalls, isEmpty);
      expect(service.containerLogCalls, isEmpty);
      expect(service.leaseCalls, isEmpty);
      expect(service.releaseCalls, isEmpty);

      service.inventoryError = null;
      await controller.refresh();

      expect(controller.state.inventory, same(inventory));
      expect(controller.state.availability, ConnectionAvailability.available);
      expect(controller.state.isConnected, isTrue);
      expect(controller.state.canMutate, isTrue);
    },
  );

  test(
    'successful action remains recorded when its follow-up refresh fails',
    () async {
      final project = projectFixture();
      final inventory = emptyInventory(projects: <CoordinatorProject>[project]);
      final service = FakeCoordinatorService(inventory: inventory);
      final controller = await _connectedController(service);
      addTearDown(controller.dispose);

      service.inventoryError = StateError('post-action refresh offline');
      await controller.runProjectAction(project, CoordinatorProjectAction.stop);

      expect(service.projectActions, hasLength(1));
      expect(controller.state.lastActionResult, same(service.actionResponse));
      expect(controller.state.lastActionLabel, 'Stop Project One');
      expect(controller.state.inventory, same(inventory));
      expect(controller.state.availability, ConnectionAvailability.stale);
      expect(controller.state.canMutate, isFalse);
      expect(
        controller.state.connectionError,
        allOf(contains('completed'), contains('post-action refresh offline')),
      );
      expect(controller.state.actionKey, isNull);
    },
  );

  test(
    'successful lease is returned and revealed when its follow-up refresh fails',
    () async {
      final project = projectFixture();
      final server = _serverFixture();
      final lease = leaseFixture(port: 3555);
      final inventory = emptyInventory(
        projects: <CoordinatorProject>[project],
        servers: <CoordinatorServer>[server],
      );
      final service = FakeCoordinatorService(inventory: inventory)
        ..leaseResponse = lease;
      final controller = await _connectedController(service);
      addTearDown(controller.dispose);

      service.inventoryError = StateError('post-lease refresh offline');
      final returned = await controller.leasePort(
        project: project,
        server: server,
        firstPort: 3500,
        lastPort: 3599,
        preferredPort: 3555,
      );

      expect(returned, same(lease));
      expect(service.leaseCalls, hasLength(1));
      expect(controller.state.lastLease, same(lease));
      expect(controller.state.inventory, same(inventory));
      expect(controller.state.availability, ConnectionAvailability.stale);
      expect(controller.state.canMutate, isFalse);
      expect(
        controller.state.connectionError,
        allOf(contains('was leased'), contains('post-lease refresh offline')),
      );
      expect(controller.state.actionKey, isNull);
    },
  );

  test(
    'unknown mutation outcome is stale and cannot be retried before refresh',
    () async {
      final project = projectFixture();
      final service =
          FakeCoordinatorService(
              inventory: emptyInventory(
                projects: <CoordinatorProject>[project],
              ),
            )
            ..projectActionError =
                const CoordinatorMutationOutcomeUnknownException(
                  method: 'POST',
                  path: '/v1/projects/restart',
                  timeout: Duration(seconds: 30),
                );
      final controller = await _connectedController(service);
      addTearDown(controller.dispose);

      await controller.runProjectAction(
        project,
        CoordinatorProjectAction.restart,
      );

      expect(service.projectActions, hasLength(1));
      expect(controller.state.lastActionResult, isNull);
      expect(controller.state.availability, ConnectionAvailability.stale);
      expect(controller.state.canMutate, isFalse);
      expect(
        controller.state.connectionError,
        allOf(contains('may have completed'), contains('Refresh')),
      );

      controller.clearMessage();
      await controller.runProjectAction(
        project,
        CoordinatorProjectAction.restart,
      );

      expect(service.projectActions, hasLength(1));
      expect(controller.state.availability, ConnectionAvailability.stale);

      await controller.refresh();

      expect(controller.state.availability, ConnectionAvailability.available);
      expect(controller.state.canMutate, isTrue);
    },
  );

  test(
    'controller rejects every remote family not advertised by meta',
    () async {
      final project = projectFixture();
      final server = _serverFixture();
      final container = _containerFixture();
      final lease = leaseFixture();
      final service = FakeCoordinatorService(
        inventory: emptyInventory(
          projects: <CoordinatorProject>[project],
          servers: <CoordinatorServer>[server],
          containers: <CoordinatorContainer>[container],
          leases: <CoordinatorLease>[lease],
        ),
        capabilities: const <CoordinatorCapability>[
          CoordinatorCapability.inventoryRead,
        ],
      );
      final controller = await _connectedController(service);
      addTearDown(controller.dispose);

      await controller.runServerAction(server, CoordinatorResourceAction.stop);
      await controller.runProjectAction(project, CoordinatorProjectAction.stop);
      await controller.runContainerAction(
        container,
        CoordinatorResourceAction.stop,
      );
      expect(await controller.readServerLogs(server), isNull);
      expect(await controller.readContainerLogs(container), isNull);
      expect(
        await controller.leasePort(
          project: project,
          server: server,
          firstPort: 3000,
          lastPort: 3999,
        ),
        isNull,
      );
      await controller.releasePort(lease);

      expect(service.serverActions, isEmpty);
      expect(service.projectActions, isEmpty);
      expect(service.containerActions, isEmpty);
      expect(service.serverLogCalls, isEmpty);
      expect(service.containerLogCalls, isEmpty);
      expect(service.leaseCalls, isEmpty);
      expect(service.releaseCalls, isEmpty);
      expect(controller.state.availability, ConnectionAvailability.available);
    },
  );

  test('refresh cannot race an in-flight mutation', () async {
    final project = projectFixture();
    final gate = Completer<void>();
    final service = FakeCoordinatorService(
      inventory: emptyInventory(projects: <CoordinatorProject>[project]),
    )..projectActionGate = gate;
    final controller = await _connectedController(service);
    addTearDown(controller.dispose);

    final action = controller.runProjectAction(
      project,
      CoordinatorProjectAction.stop,
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.projectActions, hasLength(1));
    expect(controller.state.actionKey, isNotNull);
    expect(controller.state.canRefresh, isFalse);

    await controller.refresh();

    expect(service.loadCount, 1);

    gate.complete();
    await action;

    expect(service.loadCount, 2);
    expect(controller.state.actionKey, isNull);
    expect(controller.state.canRefresh, isTrue);
  });

  test(
    'last action label never falls back to a private project identifier',
    () async {
      final project = projectFixture(
        id: 'internal-secret-id',
        root: '/work/phoenix',
        displayName: '',
      );
      final service = FakeCoordinatorService(
        inventory: emptyInventory(projects: <CoordinatorProject>[project]),
      );
      final controller = await _connectedController(service);
      addTearDown(controller.dispose);

      await controller.runProjectAction(project, CoordinatorProjectAction.stop);

      expect(controller.state.lastActionLabel, 'Stop project');
      expect(
        controller.state.lastActionLabel,
        allOf(
          isNot(contains('internal-secret-id')),
          isNot(contains('phoenix')),
        ),
      );
    },
  );

  testWidgets(
    'stale project snapshot keeps its mutation buttons disabled after dismiss',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = projectFixture();
      final service = FakeCoordinatorService(
        inventory: emptyInventory(projects: <CoordinatorProject>[project]),
      );
      final controller = await _connectedController(service);
      addTearDown(controller.dispose);
      service.inventoryError = StateError('refresh failed');
      await controller.refresh();
      controller.clearMessage();
      controller.selectSection(AppSection.projects);

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.textContaining('read-only until refresh'), findsOne);
      for (final label in <String>['Start', 'Restart', 'Stop']) {
        final button = tester.widget<AppButton>(
          find.widgetWithText(AppButton, label),
        );
        expect(button.onPressed, isNull, reason: '$label must be disabled');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'startup fence blocks project start and restart but keeps stop available',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = projectFixture(startupFenced: true);
      final controller = await _connectedController(
        FakeCoordinatorService(
          inventory: emptyInventory(projects: <CoordinatorProject>[project]),
        ),
      );
      addTearDown(controller.dispose);
      controller.selectSection(AppSection.projects);

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      final start = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Start'),
      );
      final restart = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Restart'),
      );
      final stop = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Stop'),
      );
      expect(start.onPressed, isNull);
      expect(restart.onPressed, isNull);
      expect(stop.onPressed, isNotNull);
      expect(
        find.textContaining('blocked by the committed startup fence'),
        findsOne,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'container controls follow advertised lifecycle and log capabilities',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = _containerFixture();
      final controller = await _connectedController(
        FakeCoordinatorService(
          inventory: emptyInventory(
            projects: <CoordinatorProject>[projectFixture()],
            containers: <CoordinatorContainer>[container],
          ),
          capabilities: const <CoordinatorCapability>[
            CoordinatorCapability.inventoryRead,
            CoordinatorCapability.logsRead,
          ],
        ),
      );
      addTearDown(controller.dispose);
      controller.selectSection(AppSection.containers);

      await tester.pumpWidget(DevCoordinatorApp(controller: controller));
      await tester.pumpAndSettle();

      final logs = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Logs'),
      );
      final restart = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Restart'),
      );
      final stop = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Stop'),
      );
      expect(logs.onPressed, isNotNull);
      expect(restart.onPressed, isNull);
      expect(stop.onPressed, isNull);
      expect(
        find.textContaining(
          'connection contract does not support container lifecycle',
        ),
        findsOne,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<AppController> _connectedController(
  FakeCoordinatorService service,
) async {
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
  await controller.initialize();
  return controller;
}

CoordinatorServer _serverFixture() {
  return CoordinatorServer(
    id: 'server-1',
    repoId: 'repo-1',
    projectRoot: '/work/repo-1',
    name: 'Server One',
    status: 'running',
    arguments: const <String>['serve'],
    port: 3210,
  );
}

CoordinatorContainer _containerFixture() {
  return CoordinatorContainer(
    id: 'container-1',
    containerId:
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    repoId: 'repo-1',
    projectRoot: '/work/repo-1',
    name: 'Container One',
    status: 'running',
    ports: const <CoordinatorPortBinding>[],
  );
}
