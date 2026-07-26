import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator/app/app.dart';
import 'package:devcoordinator/app/app_controller.dart';
import 'package:devcoordinator/app/app_services.dart';
import 'package:devcoordinator/app/app_state.dart';
import 'package:devcoordinator/core/storage/settings_store.dart';
import 'package:devcoordinator/features/shell/app_shell.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:release_update/release_update.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android first run offers only the native gateway and never reads a legacy token',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        _setViewport(tester, const Size(390, 844));

        final tokenStore = FakeTokenStore(value: 'must-not-be-read');
        final service = FakeCoordinatorService();
        final factory = FakeCoordinatorServiceFactory(service: service);
        final controller = AppController(
          settingsStore: FakeSettingsStore(
            const PersistedAppSettings(updateChecksEnabled: false),
          ),
          tokenStore: tokenStore,
          coordinatorFactory: factory,
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        await tester.pumpWidget(DevCoordinatorApp(controller: controller));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('connection-setup')),
          findsOne,
        );
        expect(find.text('Sign in securely'), findsOne);
        expect(find.text('https://console.classified.guru/api/v2'), findsOne);
        expect(find.text('Coordinator token'), findsNothing);
        expect(find.text('Host name'), findsNothing);
        expect(find.text('Endpoint URL'), findsNothing);
        expect(find.text('Action attribution'), findsNothing);
        expect(find.text('Local desktop'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(tokenStore.readCount, 0);
        expect(factory.attempts, isEmpty);

        final signInButton = tester.widget<AppButton>(
          find.widgetWithText(AppButton, 'Sign in securely'),
        );
        expect(signInButton.onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'cold macOS launch prefills only host details and requires the token again',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        _setViewport(tester, const Size(600, 900));
        final profile = localProfile(label: 'Saved workstation');
        final tokenStore = FakeTokenStore(
          persistedLegacyValue: 'must-never-be-returned',
        );
        final factory = FakeCoordinatorServiceFactory(
          service: FakeCoordinatorService(),
        );
        final controller = AppController(
          settingsStore: FakeSettingsStore(
            PersistedAppSettings(
              updateChecksEnabled: false,
              connection: profile,
            ),
          ),
          tokenStore: tokenStore,
          coordinatorFactory: factory,
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        await tester.pumpWidget(DevCoordinatorApp(controller: controller));
        await tester.pumpAndSettle();

        expect(factory.attempts, isEmpty);
        expect(tokenStore.value, isNull);
        expect(tokenStore.persistedLegacyValue, isNull);
        expect(find.text('Saved workstation'), findsOne);
        expect(
          find.text('Kept only in memory until this app process closes.'),
          findsOne,
        );
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'Coordinator token'),
              )
              .controller
              ?.text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'pending credential cleanup blocks reconnect and exposes a focused retry',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        _setViewport(tester, const Size(600, 900));
        final settingsStore = FakeSettingsStore(
          PersistedAppSettings(
            updateChecksEnabled: false,
            connection: localProfile(),
            credentialCleanupPending: true,
          ),
        );
        final tokenStore = FakeTokenStore(value: 's' * 40)
          ..clearError = StateError('keychain locked');
        final factory = FakeCoordinatorServiceFactory(
          service: FakeCoordinatorService(),
        );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: factory,
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await tester.pumpWidget(DevCoordinatorApp(controller: controller));
        await tester.pumpAndSettle();

        expect(find.text('Saved credential cleanup is pending'), findsOne);
        expect(
          find.widgetWithText(AppButton, 'Retry credential cleanup'),
          findsOne,
        );
        expect(factory.attempts, isEmpty);
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, 'Connect'))
              .onPressed,
          isNull,
        );

        tokenStore.clearError = null;
        await tester.tap(
          find.widgetWithText(AppButton, 'Retry credential cleanup'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Saved credential cleanup is pending'), findsNothing);
        expect(tokenStore.value, isNull);
        expect(settingsStore.value.credentialCleanupPending, isFalse);
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, 'Connect'))
              .onPressed,
          isNotNull,
        );
        expect(factory.attempts, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'completed cleanup hides retry UI after a transient marker failure',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        _setViewport(tester, const Size(600, 900));
        final settingsStore =
            FakeSettingsStore(
                PersistedAppSettings(
                  updateChecksEnabled: false,
                  connection: localProfile(),
                ),
              )
              ..queuedCleanupMarkerErrors.addAll(<Object?>[
                StateError('marker temporarily unavailable'),
                null,
              ]);
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: FakeTokenStore(value: 's' * 40),
          coordinatorFactory: FakeCoordinatorServiceFactory(
            service: FakeCoordinatorService(),
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.disconnect();
        await tester.pumpWidget(DevCoordinatorApp(controller: controller));
        await tester.pumpAndSettle();

        expect(controller.state.connectionError, isNull);
        expect(controller.state.settings.credentialCleanupPending, isFalse);
        expect(find.text('Saved credential cleanup is pending'), findsNothing);
        expect(
          find.widgetWithText(AppButton, 'Retry credential cleanup'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('connected shell renders at a wide desktop viewport', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 900));
    final setup = await _connectedSetup(
      emptyInventory(projects: <CoordinatorProject>[projectFixture()]),
    );
    addTearDown(setup.controller.dispose);

    await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOne);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Projects'), findsWidgets);
    expect(find.text('Servers'), findsWidgets);
    expect(find.text('Containers'), findsWidgets);
    expect(find.text('Ports'), findsWidgets);
    expect(find.text('Events'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected shell renders at a 390px compact viewport', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final setup = await _connectedSetup(
      emptyInventory(projects: <CoordinatorProject>[projectFixture()]),
    );
    addTearDown(setup.controller.dispose);

    await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOne);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('More'), findsOne);
    expect(
      find.byKey(const ValueKey<String>('connection-setup')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('style and brightness switch independently at runtime', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 900));
    final settingsStore = FakeSettingsStore(
      PersistedAppSettings(
        styleName: VisualStyle.oneUiInspired.storageValue,
        brightnessName: ThemeModePreference.light.storageValue,
        updateChecksEnabled: false,
        connection: localProfile(),
      ),
    );
    final controller = AppController(
      settingsStore: settingsStore,
      tokenStore: FakeTokenStore(value: 't' * 40),
      coordinatorFactory: FakeCoordinatorServiceFactory(
        service: FakeCoordinatorService(
          inventory: emptyInventory(
            projects: <CoordinatorProject>[projectFixture()],
          ),
        ),
      ),
      updateService: FakeUpdateService(),
      packageInfoLoader: packageInfoFixture,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.selectSection(AppSection.settings);

    await tester.pumpWidget(DevCoordinatorApp(controller: controller));
    await tester.pumpAndSettle();
    expect(_shellTheme(tester).brightness, Brightness.light);
    expect(
      _shellTheme(tester).extension<AppThemeTokens>()!.visualStyle,
      VisualStyle.oneUiInspired,
    );

    await tester.tap(find.text('iOS / Cupertino'));
    await tester.pumpAndSettle();

    expect(controller.state.appearance.visualStyle, VisualStyle.cupertino);
    expect(controller.state.appearance.themeMode, ThemeModePreference.light);
    expect(find.byType(CupertinoPageScaffold), findsOne);
    expect(
      _shellTheme(tester).extension<AppThemeTokens>()!.visualStyle,
      VisualStyle.cupertino,
    );

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(controller.state.appearance.visualStyle, VisualStyle.cupertino);
    expect(controller.state.appearance.themeMode, ThemeModePreference.dark);
    expect(_shellTheme(tester).brightness, Brightness.dark);

    await tester.tap(find.text('Material 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(controller.state.appearance.visualStyle, VisualStyle.material);
    expect(controller.state.appearance.themeMode, ThemeModePreference.light);
    expect(_shellTheme(tester).brightness, Brightness.light);
    expect(find.byType(Scaffold), findsOne);
    expect(settingsStore.writes, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed update launch keeps the prompt open and retry closes it only after success',
    (tester) async {
      _setViewport(tester, const Size(1200, 900));
      final release = releaseFixture();
      final updateService = FakeUpdateService()
        ..result = AppUpdateResult(
          release: release,
          message: '2.0.0 is available',
        )
        ..queuedOpenErrors.add(StateError('platform launcher unavailable'));
      final setup = await _connectedSetup(
        emptyInventory(),
        updateService: updateService,
      );
      addTearDown(setup.controller.dispose);

      await setup.controller.checkForUpdates(manual: true);
      await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOne);
      expect(find.text('DevCoordinator 2.0.0 is available'), findsOne);

      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOne);
      expect(
        find.byKey(const ValueKey<String>('update-action-error')),
        findsOne,
      );
      expect(find.widgetWithText(AppButton, 'Try again'), findsOne);
      expect(updateService.openAttempts, <ReleaseInfo>[release]);
      expect(updateService.opened, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(AppButton, 'Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(updateService.openAttempts, <ReleaseInfo>[release, release]);
      expect(updateService.opened, <ReleaseInfo>[release]);

      await setup.controller.checkForUpdates(manual: true);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario
      in <({String name, String label, bool ignore, String guidance})>[
        (
          name: 'ignore',
          label: 'Skip this version',
          ignore: true,
          guidance: 'choice to skip this version could not be saved',
        ),
        (
          name: 'later',
          label: 'Later',
          ignore: false,
          guidance: 'reminder could not be saved',
        ),
      ]) {
    testWidgets(
      '${scenario.name} persistence failure keeps update prompt retryable',
      (tester) async {
        _setViewport(tester, const Size(1200, 900));
        final release = releaseFixture();
        final updateService = FakeUpdateService()
          ..result = AppUpdateResult(
            release: release,
            message: '2.0.0 is available',
          );
        final setup = await _connectedSetup(
          emptyInventory(),
          updateService: updateService,
        );
        addTearDown(setup.controller.dispose);
        await setup.controller.checkForUpdates(manual: true);
        setup.settingsStore.queuedWriteErrors.add(
          StateError('settings disk full'),
        );

        await tester.pumpWidget(
          DevCoordinatorApp(controller: setup.controller),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AppButton, scenario.label));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOne);
        expect(
          find.byKey(const ValueKey<String>('update-action-error')),
          findsOne,
        );
        expect(find.textContaining(scenario.guidance), findsOne);
        expect(find.textContaining('settings disk full'), findsOne);
        expect(setup.controller.state.availableRelease, same(release));
        expect(
          setup.controller.state.updateMessageKind,
          UpdateMessageKind.error,
        );
        if (scenario.ignore) {
          expect(updateService.ignored, <ReleaseInfo>[release]);
          expect(updateService.deferred, isEmpty);
        } else {
          expect(updateService.deferred, <ReleaseInfo>[release]);
          expect(updateService.ignored, isEmpty);
        }
        expect(tester.takeException(), isNull);

        await tester.tap(find.widgetWithText(AppButton, scenario.label));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(setup.controller.state.availableRelease, isNull);
        expect(setup.controller.state.updateMessage, isNull);
        expect(setup.controller.state.updateMessageKind, isNull);
        if (scenario.ignore) {
          expect(updateService.ignored, <ReleaseInfo>[release, release]);
        } else {
          expect(updateService.deferred, <ReleaseInfo>[release, release]);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('manual update failure uses the typed danger status', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 900));
    final updateService = FakeUpdateService()
      ..checkError = StateError('release service offline');
    final setup = await _connectedSetup(
      emptyInventory(),
      updateService: updateService,
    );
    addTearDown(setup.controller.dispose);
    setup.controller.selectSection(AppSection.settings);

    await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
    await tester.pumpAndSettle();
    final checkButton = find.widgetWithText(AppButton, 'Check for updates');
    await tester.ensureVisible(checkButton);
    await tester.pumpAndSettle();
    await tester.tap(checkButton);
    await tester.pumpAndSettle();

    final message = find.textContaining('release service offline');
    expect(message, findsOne);
    final status = tester.widget<AppStatus>(
      find.ancestor(of: message, matching: find.byType(AppStatus)),
    );
    expect(status.tone, AppStatusTone.danger);
    expect(setup.controller.state.updateMessageKind, UpdateMessageKind.error);

    updateService
      ..checkError = null
      ..result = const AppUpdateResult(
        message: 'You are using the latest release.',
      );
    await tester.tap(checkButton);
    await tester.pumpAndSettle();

    final currentMessage = find.text('You are using the latest release.');
    expect(currentMessage, findsOne);
    final currentStatus = tester.widget<AppStatus>(
      find.ancestor(of: currentMessage, matching: find.byType(AppStatus)),
    );
    expect(currentStatus.tone, AppStatusTone.info);
    expect(
      setup.controller.state.updateMessageKind,
      UpdateMessageKind.informational,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'root provides high-contrast themes and reacts to reduced-motion flags',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final setup = await _connectedSetup(emptyInventory());
      addTearDown(setup.controller.dispose);

      await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
      await tester.pumpAndSettle();

      var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.highContrastTheme!.extension<AppThemeTokens>()!.isHighContrast,
        isTrue,
      );
      expect(
        app.highContrastDarkTheme!.extension<AppThemeTokens>()!.isHighContrast,
        isTrue,
      );
      expect(app.themeAnimationDuration, const Duration(milliseconds: 240));

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      await tester.pumpAndSettle();
      expect(
        _shellTheme(tester).extension<AppThemeTokens>()!.isHighContrast,
        isTrue,
      );

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeAnimationDuration, Duration.zero);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pump();
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeAnimationDuration, Duration.zero);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeAnimationDuration, const Duration(milliseconds: 240));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('foreground resume triggers the scheduled update adapter', (
    tester,
  ) async {
    final updateService = FakeUpdateService();
    final controller = AppController(
      settingsStore: FakeSettingsStore(
        const PersistedAppSettings(updateChecksEnabled: true),
      ),
      tokenStore: FakeTokenStore(),
      coordinatorFactory: FakeCoordinatorServiceFactory(
        service: FakeCoordinatorService(),
      ),
      updateService: updateService,
      packageInfoLoader: packageInfoFixture,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(DevCoordinatorApp(controller: controller));
    await tester.pumpAndSettle();
    expect(updateService.checks, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(updateService.checks, hasLength(2));
    expect(updateService.checks.last.manual, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Ports leads with the real empty collection and opens an in-view lease flow',
    (tester) async {
      _setViewport(tester, const Size(390, 844));
      final project = projectFixture();
      final server = enrolledServerFixture();
      final lease = leaseFixture(port: 3333);
      final initial = emptyInventory(
        projects: <CoordinatorProject>[project],
        servers: <CoordinatorServer>[server],
      );
      final leased = emptyInventory(
        projects: <CoordinatorProject>[project],
        servers: <CoordinatorServer>[server],
        leases: <CoordinatorLease>[lease],
      );
      final service = FakeCoordinatorService(
        inventories: <CoordinatorInventory>[initial, leased],
      )..leaseResponse = lease;
      final setup = await _connectedSetup(initial, service: service);
      addTearDown(setup.controller.dispose);
      setup.controller.selectSection(AppSection.ports);

      await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
      await tester.pumpAndSettle();

      final count = find.text('0 visible leases');
      final create = find.widgetWithText(AppButton, 'Lease a port');
      final empty = find.text('No active or retained port leases are visible.');
      expect(count, findsOne);
      expect(create, findsOne);
      expect(empty, findsOne);
      expect(
        tester.getTopLeft(count).dy,
        lessThan(tester.getTopLeft(empty).dy),
      );
      expect(
        tester.getTopLeft(create).dy,
        lessThan(tester.getTopLeft(empty).dy),
      );

      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOne);
      expect(find.text('Enrolled server'), findsOne);
      expect(find.text('Server One'), findsOne);
      expect(find.text('Allowed range'), findsOne);
      expect(find.text('Preferred port (optional)'), findsOne);
      expect(find.text('Lease time, seconds (optional)'), findsOne);
      expect(tester.binding.focusManager.primaryFocus, isNotNull);

      await tester.tap(find.widgetWithText(AppButton, 'Lease'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(service.leaseCalls, hasLength(1));
      expect(service.leaseCalls.single.server, same(server));
      expect(service.leaseCalls.single.firstPort, 3000);
      expect(service.leaseCalls.single.lastPort, 3999);
      expect(service.leaseCalls.single.ttl, const Duration(seconds: 3600));
      expect(setup.controller.state.lastLease, same(lease));
      expect(find.textContaining('Port 3333 was leased'), findsOne);
      expect(find.text('3333'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ports disables leasing honestly when no exactly owned enrolled server exists',
    (tester) async {
      _setViewport(tester, const Size(600, 900));
      final project = projectFixture();
      final mismatchedServer = enrolledServerFixture(
        id: 'server-mismatched',
        repoId: project.id,
        projectRoot: '/work/another-project',
      );
      final inventory = emptyInventory(
        projects: <CoordinatorProject>[project],
        servers: <CoordinatorServer>[mismatchedServer],
      );
      final setup = await _connectedSetup(inventory);
      addTearDown(setup.controller.dispose);
      setup.controller.selectSection(AppSection.ports);

      await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
      await tester.pumpAndSettle();

      final create = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Lease a port'),
      );
      expect(create.onPressed, isNull);
      expect(
        find.textContaining(
          'requires an enrolled server with exact project ownership',
        ),
        findsOne,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Port lease selection is ownership-filtered and duplicate-safe', (
    tester,
  ) async {
    _setViewport(tester, const Size(600, 900));
    const privateServerIdA = 'private-server-definition-a';
    const privateOtherServerId = 'private-server-definition-other';
    const privateProjectRoot = '/private/customer/project-a';
    final project = projectFixture(root: privateProjectRoot);
    final otherProject = projectFixture(
      id: 'repo-2',
      root: '/private/customer/project-b',
      displayName: project.displayName,
    );
    final serverA = enrolledServerFixture(
      id: privateServerIdA,
      projectRoot: privateProjectRoot,
      name: 'API',
    );
    final otherServer = enrolledServerFixture(
      id: privateOtherServerId,
      repoId: otherProject.id,
      projectRoot: otherProject.canonicalRoot,
      name: 'Other project server',
    );
    final lease = leaseFixture();
    final initial = emptyInventory(
      projects: <CoordinatorProject>[project, otherProject],
      servers: <CoordinatorServer>[otherServer, serverA],
    );
    final leased = emptyInventory(
      projects: <CoordinatorProject>[project, otherProject],
      servers: <CoordinatorServer>[otherServer, serverA],
      leases: <CoordinatorLease>[lease],
    );
    final service = FakeCoordinatorService(
      inventories: <CoordinatorInventory>[initial, leased],
    )..leaseResponse = lease;
    final setup = await _connectedSetup(initial, service: service);
    addTearDown(setup.controller.dispose);
    setup.controller.selectSection(AppSection.ports);

    await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Lease a port'));
    await tester.pumpAndSettle();

    final serverDropdown = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<CoordinatorServer>,
    );
    expect(serverDropdown, findsOne);
    expect(find.text('Project One · 1/2'), findsOne);
    await tester.tap(serverDropdown);
    await tester.pumpAndSettle();

    expect(find.text('API'), findsWidgets);
    expect(find.text('Other project server'), findsNothing);
    for (final privateValue in <String>[
      privateServerIdA,
      privateOtherServerId,
      privateProjectRoot,
      otherProject.canonicalRoot,
    ]) {
      expect(find.textContaining(privateValue), findsNothing);
    }

    await tester.tap(find.text('API').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Lease'));
    await tester.pumpAndSettle();

    expect(service.leaseCalls, hasLength(1));
    expect(service.leaseCalls.single.project, same(project));
    expect(service.leaseCalls.single.server, same(serverA));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Servers expose controls only for conclusive lifecycle states', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 1600));
    final project = projectFixture();
    final stopped = enrolledServerFixture(
      id: 'server-stopped',
      name: 'Stopped server',
      port: 3201,
      healthClassification: 'stopped',
      healthOk: false,
    );
    final running = enrolledServerFixture(
      id: 'server-running',
      name: 'Running server',
      status: 'running',
      port: 3202,
      healthClassification: 'healthy',
      healthOk: true,
    );
    final starting = enrolledServerFixture(
      id: 'server-starting',
      name: 'Starting server',
      status: 'starting',
      port: 3203,
      healthClassification: 'starting',
    );
    final wrongListener = enrolledServerFixture(
      id: 'server-wrong-listener',
      name: 'Wrong listener server',
      status: 'running',
      port: 3204,
      healthClassification: 'wrong-listener',
    );
    final inventory = emptyInventory(
      projects: <CoordinatorProject>[project],
      servers: <CoordinatorServer>[stopped, running, starting, wrongListener],
    );
    final setup = await _connectedSetup(inventory);
    addTearDown(setup.controller.dispose);
    setup.controller.selectSection(AppSection.servers);

    await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppButton, 'Start'), findsOne);
    expect(find.widgetWithText(AppButton, 'Restart'), findsOne);
    expect(find.widgetWithText(AppButton, 'Stop'), findsOne);
    expect(
      find.textContaining(
        'lifecycle state and listener identity are conclusive',
      ),
      findsNWidgets(2),
    );
    for (final label in <String>['Start', 'Restart', 'Stop']) {
      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, label),
      );
      expect(button.onPressed, isNotNull, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ports disable release for retained and time-expired leases', (
    tester,
  ) async {
    _setViewport(tester, const Size(1200, 1400));
    final project = projectFixture();
    final server = enrolledServerFixture();
    final active = leaseFixture(
      id: 'active',
      port: 3210,
      expiresAt: DateTime.utc(2100),
    );
    final released = leaseFixture(
      id: 'released',
      port: 3211,
      status: 'released',
    );
    final expired = leaseFixture(
      id: 'expired',
      port: 3212,
      expiresAt: DateTime.utc(2000),
    );
    final inventory = emptyInventory(
      projects: <CoordinatorProject>[project],
      servers: <CoordinatorServer>[server],
      leases: <CoordinatorLease>[active, released, expired],
    );
    final setup = await _connectedSetup(inventory);
    addTearDown(setup.controller.dispose);
    setup.controller.selectSection(AppSection.ports);

    await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
    await tester.pumpAndSettle();

    final releaseButtons = tester
        .widgetList<AppButton>(find.widgetWithText(AppButton, 'Release'))
        .toList();
    expect(releaseButtons, hasLength(3));
    expect(
      releaseButtons.where((button) => button.onPressed != null),
      hasLength(1),
    );
    expect(
      find.textContaining('retained lease is no longer active'),
      findsNWidgets(2),
    );
    expect(find.textContaining('Expires '), findsOne);
    expect(find.textContaining('Expired '), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Events identify the bounded recent inventory snapshot', (
    tester,
  ) async {
    _setViewport(tester, const Size(600, 900));
    final event = CoordinatorEvent(
      id: 'event-1',
      kind: 'server.health',
      code: 'server_healthy',
      message: 'Server recovered',
      occurredAt: DateTime.utc(2026, 7, 25, 12),
    );
    final inventory = emptyInventory(events: <CoordinatorEvent>[event]);
    final setup = await _connectedSetup(inventory);
    addTearDown(setup.controller.dispose);
    setup.controller.selectSection(AppSection.events);

    await tester.pumpWidget(DevCoordinatorApp(controller: setup.controller));
    await tester.pumpAndSettle();

    expect(find.textContaining('Recent inventory snapshot'), findsOne);
    expect(find.text('Server recovered'), findsOne);
    expect(find.textContaining('durable cursor'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ThemeData _shellTheme(WidgetTester tester) {
  final context = tester.element(find.byType(UniversalAppShell));
  return Theme.of(context);
}

Future<
  ({
    AppController controller,
    FakeCoordinatorService service,
    FakeSettingsStore settingsStore,
  })
>
_connectedSetup(
  CoordinatorInventory inventory, {
  FakeCoordinatorService? service,
  FakeUpdateService? updateService,
}) async {
  final coordinator = service ?? FakeCoordinatorService(inventory: inventory);
  final settingsStore = FakeSettingsStore(
    PersistedAppSettings(
      updateChecksEnabled: false,
      connection: localProfile(),
    ),
  );
  final controller = AppController(
    settingsStore: settingsStore,
    tokenStore: FakeTokenStore(value: 't' * 40),
    coordinatorFactory: FakeCoordinatorServiceFactory(service: coordinator),
    updateService: updateService ?? FakeUpdateService(),
    packageInfoLoader: packageInfoFixture,
  );
  await controller.initialize();
  return (
    controller: controller,
    service: coordinator,
    settingsStore: settingsStore,
  );
}
