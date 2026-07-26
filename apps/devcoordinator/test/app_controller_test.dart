import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator/app/app_controller.dart';
import 'package:devcoordinator/app/app_services.dart';
import 'package:devcoordinator/app/app_state.dart';
import 'package:devcoordinator/core/storage/settings_store.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:release_update/release_update.dart';

import 'support/fakes.dart';

void main() {
  group('AppController initialization', () {
    test(
      'loads appearance and reconnects only with a process-session credential',
      () async {
        final events = <String>[];
        final profile = localProfile();
        final inventory = emptyInventory(
          projects: <CoordinatorProject>[projectFixture()],
        );
        final settingsStore = FakeSettingsStore(
          PersistedAppSettings(
            styleName: VisualStyle.cupertino.storageValue,
            brightnessName: ThemeModePreference.dark.storageValue,
            updateChecksEnabled: false,
            connection: profile,
          ),
          events: events,
        );
        final tokenStore = FakeTokenStore(value: 's' * 40, events: events);
        final service = FakeCoordinatorService(
          inventory: inventory,
          events: events,
        );
        final factory = FakeCoordinatorServiceFactory(
          service: service,
          events: events,
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

        expect(controller.state.busy, isFalse);
        expect(controller.state.isConnected, isTrue);
        expect(controller.state.inventory, same(inventory));
        expect(
          controller.state.appearance,
          const AppearancePreferences(
            visualStyle: VisualStyle.cupertino,
            themeMode: ThemeModePreference.dark,
          ),
        );
        expect(tokenStore.readCount, 1);
        expect(tokenStore.purgeLegacyCount, 1);
        expect(factory.attempts, hasLength(1));
        expect(factory.attempts.single.profile, same(profile));
        expect(factory.attempts.single.credential, 's' * 40);
        expect(events, <String>[
          'settings.read',
          'token.purgeLegacy',
          'token.read',
          'factory.connect',
          'service.loadInventory',
        ]);
      },
    );

    test(
      'cold launch purges an orphaned legacy key without a profile or marker',
      () async {
        final tokenStore = FakeTokenStore(
          persistedLegacyValue: 'orphaned-pre-session-value',
        );
        final controller = AppController(
          settingsStore: FakeSettingsStore(
            const PersistedAppSettings(updateChecksEnabled: false),
          ),
          tokenStore: tokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(
            service: FakeCoordinatorService(),
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(tokenStore.purgeLegacyCount, 1);
        expect(tokenStore.readCount, 0);
        expect(tokenStore.persistedLegacyValue, isNull);
        expect(controller.state.settings.credentialCleanupPending, isFalse);
        expect(controller.state.connectionError, isNull);
      },
    );

    test(
      'failed orphan purge is gated and retried on the next cold launch',
      () async {
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(updateChecksEnabled: false),
        );
        final firstTokenStore = FakeTokenStore(
          persistedLegacyValue: 'orphaned-pre-session-value',
        )..clearError = StateError('keychain locked');
        final firstController = AppController(
          settingsStore: settingsStore,
          tokenStore: firstTokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(
            service: FakeCoordinatorService(),
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(firstController.dispose);

        await firstController.initialize();

        expect(firstTokenStore.purgeLegacyCount, 2);
        expect(firstTokenStore.readCount, 0);
        expect(firstTokenStore.persistedLegacyValue, isNotNull);
        expect(settingsStore.value.credentialCleanupPending, isTrue);
        expect(
          firstController.state.connectionError,
          contains('Retry cleanup before connecting'),
        );

        final restartedTokenStore = FakeTokenStore(
          persistedLegacyValue: firstTokenStore.persistedLegacyValue,
        );
        final restartedController = AppController(
          settingsStore: settingsStore,
          tokenStore: restartedTokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(
            service: FakeCoordinatorService(),
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(restartedController.dispose);

        await restartedController.initialize();

        expect(restartedTokenStore.purgeLegacyCount, 1);
        expect(restartedTokenStore.readCount, 0);
        expect(restartedTokenStore.persistedLegacyValue, isNull);
        expect(settingsStore.value.credentialCleanupPending, isFalse);
        expect(
          restartedController.state.settings.credentialCleanupPending,
          isFalse,
        );
        expect(restartedController.state.connectionError, isNull);
      },
    );

    test(
      'successful cold-launch purge retry retains the non-secret profile',
      () async {
        final profile = localProfile(label: 'Saved workstation');
        final settingsStore = FakeSettingsStore(
          PersistedAppSettings(updateChecksEnabled: false, connection: profile),
        );
        final tokenStore =
            FakeTokenStore(persistedLegacyValue: 'orphaned-pre-session-value')
              ..queuedClearErrors.addAll(<Object?>[
                StateError('keychain temporarily locked'),
                null,
              ]);
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

        expect(tokenStore.purgeLegacyCount, 2);
        expect(tokenStore.persistedLegacyValue, isNull);
        expect(tokenStore.readCount, 1);
        expect(tokenStore.value, isNull);
        expect(settingsStore.value.connection, same(profile));
        expect(controller.state.settings.connection, same(profile));
        expect(settingsStore.value.credentialCleanupPending, isFalse);
        expect(controller.state.settings.credentialCleanupPending, isFalse);
        expect(controller.state.connectionError, isNull);
        expect(factory.attempts, isEmpty);
      },
    );

    test(
      'does not attempt a saved connection when its credential is absent',
      () async {
        final profile = localProfile();
        final settingsStore = FakeSettingsStore(
          PersistedAppSettings(updateChecksEnabled: false, connection: profile),
        );
        final tokenStore = FakeTokenStore();
        final service = FakeCoordinatorService();
        final factory = FakeCoordinatorServiceFactory(service: service);
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: factory,
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(tokenStore.readCount, 1);
        expect(factory.attempts, isEmpty);
        expect(controller.state.inventory, isNull);
        expect(controller.state.isConnected, isFalse);
        expect(controller.state.settings.connection, same(profile));
        expect(controller.state.connectionError, isNull);
      },
    );
  });

  group('AppController connection', () {
    test(
      'validates inventory before retaining a session credential and profile',
      () async {
        final events = <String>[];
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(updateChecksEnabled: false),
          events: events,
        );
        final tokenStore = FakeTokenStore(events: events);
        final inventory = emptyInventory(
          projects: <CoordinatorProject>[projectFixture()],
        );
        final service = FakeCoordinatorService(
          inventory: inventory,
          events: events,
        );
        final factory = FakeCoordinatorServiceFactory(
          service: service,
          events: events,
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
        events.clear();

        final profile = localProfile(label: 'Desktop');
        await controller.connect(profile: profile, credential: 't' * 40);

        expect(events, <String>[
          'factory.connect',
          'service.loadInventory',
          'token.write',
          'settings.write',
        ]);
        expect(controller.state.isConnected, isTrue);
        expect(controller.state.inventory, same(inventory));
        expect(controller.state.settings.connection, same(profile));
        expect(tokenStore.value, 't' * 40);
        expect(settingsStore.writes, hasLength(1));
      },
    );

    test(
      'closes a rejected candidate and leaves no secret or profile behind',
      () async {
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(updateChecksEnabled: false),
        );
        final tokenStore = FakeTokenStore();
        final service = FakeCoordinatorService()
          ..inventoryError = StateError('inventory unavailable');
        final factory = FakeCoordinatorServiceFactory(service: service);
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: factory,
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.connect(profile: localProfile(), credential: 't' * 40);

        expect(service.closeCount, 1);
        expect(tokenStore.writeCount, 0);
        expect(settingsStore.writes, isEmpty);
        expect(controller.state.settings.connection, isNull);
        expect(controller.state.inventory, isNull);
        expect(
          controller.state.connectionError,
          contains('inventory unavailable'),
        );
      },
    );

    test(
      'session credential failure closes the candidate and restores an empty credential',
      () async {
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(updateChecksEnabled: false),
        );
        final tokenStore = FakeTokenStore()
          ..writeError = StateError('secure storage unavailable');
        final candidate = FakeCoordinatorService(
          inventory: emptyInventory(
            projects: <CoordinatorProject>[projectFixture()],
          ),
        );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(service: candidate),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.connect(
          profile: localProfile(label: 'New'),
          credential: 'n' * 40,
        );

        expect(candidate.closeCount, 1);
        expect(tokenStore.value, isNull);
        expect(tokenStore.clearCount, 1);
        expect(settingsStore.writes, isEmpty);
        expect(controller.state.settings.connection, isNull);
        expect(controller.state.inventory, isNull);
        expect(controller.state.isConnected, isFalse);
        expect(
          controller.state.connectionError,
          contains('secure storage unavailable'),
        );
      },
    );

    test(
      'settings write failure restores the prior token profile and live service',
      () async {
        final oldProfile = localProfile(label: 'Old');
        final newProfile = localProfile(
          label: 'New',
          baseUrl: 'http://127.0.0.1:39876',
        );
        final oldInventory = emptyInventory(
          projects: <CoordinatorProject>[
            projectFixture(displayName: 'Old project'),
          ],
        );
        final newInventory = emptyInventory(
          projects: <CoordinatorProject>[
            projectFixture(id: 'repo-2', displayName: 'New project'),
          ],
        );
        final settingsStore = FakeSettingsStore(
          PersistedAppSettings(
            updateChecksEnabled: false,
            connection: oldProfile,
          ),
        )..queuedWriteErrors.add(StateError('settings disk full'));
        final tokenStore = FakeTokenStore(value: 'o' * 40);
        final oldService = FakeCoordinatorService(inventory: oldInventory);
        final candidate = FakeCoordinatorService(inventory: newInventory);
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: _SequenceCoordinatorFactory(
            <FakeCoordinatorService>[oldService, candidate],
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.connect(profile: newProfile, credential: 'n' * 40);

        expect(candidate.closeCount, 1);
        expect(oldService.closeCount, 0);
        expect(tokenStore.value, 'o' * 40);
        expect(settingsStore.value.connection, same(oldProfile));
        expect(settingsStore.writes, hasLength(1));
        expect(settingsStore.writes.single.connection, same(oldProfile));
        expect(controller.state.settings.connection, same(oldProfile));
        expect(controller.state.inventory, same(oldInventory));
        expect(controller.state.isConnected, isTrue);
        expect(
          controller.state.connectionError,
          contains('settings disk full'),
        );

        await controller.refresh();
        expect(oldService.loadCount, 2);
        expect(controller.state.inventory, same(oldInventory));
      },
    );

    test(
      'rollback failure fences ambiguous credentials until cleanup succeeds',
      () async {
        final settingsStore =
            FakeSettingsStore(
                const PersistedAppSettings(updateChecksEnabled: false),
              )
              ..queuedWriteErrors.addAll(<Object?>[
                StateError('settings disk full'),
                null,
              ]);
        final tokenStore = FakeTokenStore();
        final service = FakeCoordinatorService(
          inventory: emptyInventory(
            projects: <CoordinatorProject>[projectFixture()],
          ),
        );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(service: service),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        tokenStore.queuedClearErrors.addAll(<Object?>[
          null,
          StateError('keychain locked'),
          StateError('keychain locked'),
        ]);

        await controller.connect(profile: localProfile(), credential: 'n' * 40);

        expect(service.closeCount, 1);
        expect(controller.state.isConnected, isFalse);
        expect(
          controller.state.availability,
          ConnectionAvailability.disconnected,
        );
        expect(controller.state.inventory, isNull);
        expect(controller.state.settings.credentialCleanupPending, isTrue);
        expect(settingsStore.value.connection, isNull);
        expect(settingsStore.value.credentialCleanupPending, isTrue);
        expect(tokenStore.value, isNull);
        expect(
          controller.state.connectionError,
          allOf(contains('settings disk full'), contains('keychain locked')),
        );

        tokenStore.clearError = null;
        expect(await controller.retryCredentialCleanup(), isTrue);
        expect(tokenStore.value, isNull);
        expect(settingsStore.value.credentialCleanupPending, isFalse);
      },
    );

    test(
      'disconnect closes the live service even when profile cleanup fails',
      () async {
        final profile = localProfile(label: 'Connected');
        final settingsStore = FakeSettingsStore(
          PersistedAppSettings(updateChecksEnabled: false, connection: profile),
        )..writeError = StateError('settings disk full');
        final tokenStore = FakeTokenStore(value: 's' * 40);
        final service = FakeCoordinatorService(
          inventory: emptyInventory(
            projects: <CoordinatorProject>[projectFixture()],
          ),
        );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(service: service),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.state.isConnected, isTrue);

        await controller.disconnect();

        expect(tokenStore.clearCount, 1);
        expect(tokenStore.value, isNull);
        expect(service.closeCount, 1);
        expect(controller.state.isConnected, isFalse);
        expect(
          controller.state.availability,
          ConnectionAvailability.disconnected,
        );
        expect(controller.state.inventory, isNull);
        expect(controller.state.settings.connection, isNull);
        expect(controller.state.settings.credentialCleanupPending, isTrue);
        expect(settingsStore.value.connection, same(profile));
        expect(settingsStore.value.credentialCleanupPending, isTrue);
        expect(settingsStore.cleanupMarkers, <bool>[true]);
        expect(
          controller.state.connectionError,
          allOf(contains('live connection was closed'), contains('disk full')),
        );

        await controller.refresh();
        expect(service.loadCount, 1);
      },
    );

    test(
      'transient initial cleanup-marker failure leaves a consistent success',
      () async {
        final profile = localProfile(label: 'Connected');
        final settingsStore =
            FakeSettingsStore(
                PersistedAppSettings(
                  updateChecksEnabled: false,
                  connection: profile,
                ),
              )
              ..queuedCleanupMarkerErrors.addAll(<Object?>[
                StateError('marker temporarily unavailable'),
                null,
              ]);
        final tokenStore = FakeTokenStore(value: 's' * 40);
        final service = FakeCoordinatorService(
          inventory: emptyInventory(
            projects: <CoordinatorProject>[projectFixture()],
          ),
        );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(service: service),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.disconnect();

        expect(service.closeCount, 1);
        expect(tokenStore.value, isNull);
        expect(settingsStore.value.connection, isNull);
        expect(settingsStore.value.credentialCleanupPending, isFalse);
        expect(controller.state.settings.credentialCleanupPending, isFalse);
        expect(controller.state.connectionError, isNull);
        expect(settingsStore.cleanupMarkers, <bool>[false]);
      },
    );

    test(
      'failed credential deletion persists a gate and restart never reuses it',
      () async {
        final profile = localProfile(label: 'Connected');
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(updateChecksEnabled: false),
        );
        final tokenStore = FakeTokenStore();
        final firstService = FakeCoordinatorService(
          inventory: emptyInventory(
            projects: <CoordinatorProject>[projectFixture()],
          ),
        );
        final firstController = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(
            service: firstService,
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(firstController.dispose);
        await firstController.initialize();
        await firstController.connect(profile: profile, credential: 's' * 40);
        tokenStore.persistedLegacyValue = 's' * 40;
        tokenStore.clearError = StateError('keychain locked');

        await firstController.disconnect();

        expect(tokenStore.value, isNull);
        expect(tokenStore.persistedLegacyValue, isNotNull);
        expect(settingsStore.value.connection, isNull);
        expect(settingsStore.value.credentialCleanupPending, isTrue);
        expect(firstController.state.settings.credentialCleanupPending, isTrue);

        final restartService = FakeCoordinatorService();
        final restartFactory = FakeCoordinatorServiceFactory(
          service: restartService,
        );
        final restartedController = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: restartFactory,
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(restartedController.dispose);
        await restartedController.initialize();

        expect(restartFactory.attempts, isEmpty);
        expect(restartedController.state.isConnected, isFalse);
        expect(
          restartedController.state.settings.credentialCleanupPending,
          isTrue,
        );
        expect(
          restartedController.state.connectionError,
          contains('Retry cleanup before connecting'),
        );

        tokenStore.clearError = null;
        expect(await restartedController.retryCredentialCleanup(), isTrue);

        expect(tokenStore.value, isNull);
        expect(settingsStore.value.connection, isNull);
        expect(settingsStore.value.credentialCleanupPending, isFalse);
        expect(
          restartedController.state.settings.credentialCleanupPending,
          isFalse,
        );
        expect(restartFactory.attempts, isEmpty);
      },
    );

    test(
      'combined cleanup persistence failures cannot reuse a credential after '
      'restart',
      () async {
        final profile = localProfile(label: 'Connected');
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(updateChecksEnabled: false),
        );
        final tokenStore = FakeTokenStore();
        final firstController = AppController(
          settingsStore: settingsStore,
          tokenStore: tokenStore,
          coordinatorFactory: FakeCoordinatorServiceFactory(
            service: FakeCoordinatorService(),
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(firstController.dispose);
        await firstController.initialize();
        await firstController.connect(profile: profile, credential: 's' * 40);
        expect(firstController.state.isConnected, isTrue);
        tokenStore.persistedLegacyValue = 's' * 40;

        settingsStore.cleanupMarkerError = StateError('marker disk full');
        settingsStore.writeError = StateError('profile disk full');
        tokenStore.clearError = StateError('keychain locked');
        await firstController.disconnect();

        expect(settingsStore.value.connection, same(profile));
        expect(settingsStore.value.credentialCleanupPending, isFalse);
        expect(tokenStore.value, isNull);
        expect(tokenStore.persistedLegacyValue, 's' * 40);
        expect(firstController.state.isConnected, isFalse);

        final restartedTokenStore = FakeTokenStore(
          persistedLegacyValue: tokenStore.persistedLegacyValue,
        )..clearError = tokenStore.clearError;
        final restartFactory = FakeCoordinatorServiceFactory(
          service: FakeCoordinatorService(),
        );
        final restartedController = AppController(
          settingsStore: settingsStore,
          tokenStore: restartedTokenStore,
          coordinatorFactory: restartFactory,
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(restartedController.dispose);
        await restartedController.initialize();

        expect(restartedTokenStore.readCount, 0);
        expect(restartedTokenStore.purgeLegacyCount, 2);
        expect(restartedTokenStore.value, isNull);
        expect(restartedTokenStore.persistedLegacyValue, 's' * 40);
        expect(restartFactory.attempts, isEmpty);
        expect(restartedController.state.isConnected, isFalse);
        expect(restartedController.state.inventory, isNull);
        expect(
          restartedController.state.settings.credentialCleanupPending,
          isTrue,
        );
      },
    );
  });

  group('AppController updates', () {
    test(
      'persists cache, then records ignore and remind-later suppression',
      () async {
        final originalCache = <String, Object?>{'sourceId': 'old'};
        final originalSuppression = <String, Object?>{
          'ignoredThroughVersion': null,
          'deferredThroughVersion': null,
          'deferredUntil': null,
        };
        final settingsStore = FakeSettingsStore(
          PersistedAppSettings(
            updateChecksEnabled: false,
            lastUpdateCheck: DateTime.utc(2029, 12, 31),
            releaseCache: originalCache,
            updateSuppression: originalSuppression,
          ),
        );
        final updateService = FakeUpdateService();
        final checkedAt = DateTime.utc(2030, 1, 1, 1);
        final release = releaseFixture();
        final refreshedCache = <String, Object?>{
          'sourceId': 'github:example/devcoordinator',
          'release': release.toJson(),
        };
        updateService.result = AppUpdateResult(
          release: release,
          message: '2.0.0 is available',
          checkedAt: checkedAt,
          releaseCache: refreshedCache,
          updateSuppression: originalSuppression,
        );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: FakeTokenStore(),
          coordinatorFactory: FakeCoordinatorServiceFactory(
            service: FakeCoordinatorService(),
          ),
          updateService: updateService,
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.checkForUpdates(manual: true);

        expect(updateService.checks, hasLength(1));
        final check = updateService.checks.single;
        expect(check.currentVersion, '1.0.0');
        expect(check.manual, isTrue);
        expect(check.lastCheckedAt, DateTime.utc(2029, 12, 31));
        expect(check.releaseCache, same(originalCache));
        expect(check.updateSuppression, same(originalSuppression));
        expect(controller.state.availableRelease, same(release));
        expect(controller.state.updateMessageKind, UpdateMessageKind.success);
        expect(controller.state.settings.lastUpdateCheck, checkedAt);
        expect(controller.state.settings.releaseCache, same(refreshedCache));

        await controller.ignoreAvailableRelease();

        expect(updateService.ignored, <ReleaseInfo>[release]);
        expect(controller.state.availableRelease, isNull);
        expect(
          controller.state.settings.updateSuppression,
          updateService.ignoreResult,
        );

        await controller.checkForUpdates(manual: true);
        await controller.deferAvailableRelease();

        expect(updateService.deferred, <ReleaseInfo>[release]);
        expect(controller.state.availableRelease, isNull);
        expect(
          controller.state.settings.updateSuppression,
          updateService.remindLaterResult,
        );
        expect(
          settingsStore.value.updateSuppression,
          updateService.remindLaterResult,
        );
      },
    );

    test(
      'keeps background failures quiet but reports manual failures',
      () async {
        final updateService = FakeUpdateService()
          ..checkError = StateError('release service offline');
        final controller = AppController(
          settingsStore: FakeSettingsStore(
            const PersistedAppSettings(updateChecksEnabled: false),
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

        await controller.checkForUpdates(manual: false);
        expect(controller.state.updateMessage, isNull);
        expect(controller.state.updateMessageKind, isNull);

        await controller.checkForUpdates(manual: true);
        expect(
          controller.state.updateMessage,
          contains('release service offline'),
        );
        expect(controller.state.updateMessageKind, UpdateMessageKind.error);
        expect(controller.state.checkingUpdates, isFalse);

        updateService
          ..checkError = null
          ..result = const AppUpdateResult(
            message: 'You are using the latest release.',
          );
        await controller.checkForUpdates(manual: true);

        expect(controller.state.availableRelease, isNull);
        expect(
          controller.state.updateMessageKind,
          UpdateMessageKind.informational,
        );
      },
    );

    test(
      'retains a discovered release when its cache cannot be persisted',
      () async {
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(updateChecksEnabled: false),
        )..writeError = StateError('settings disk full');
        final release = releaseFixture();
        final updateService = FakeUpdateService()
          ..result = AppUpdateResult(
            release: release,
            message: '2.0.0 is available',
            checkedAt: DateTime.utc(2030, 1, 1),
            releaseCache: <String, Object?>{'sourceId': 'github:example/repo'},
          );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: FakeTokenStore(),
          coordinatorFactory: FakeCoordinatorServiceFactory(
            service: FakeCoordinatorService(),
          ),
          updateService: updateService,
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.checkForUpdates(manual: true);

        expect(controller.state.availableRelease, same(release));
        expect(controller.state.settings.lastUpdateCheck, isNull);
        expect(controller.state.updateMessage, contains('settings disk full'));
        expect(controller.state.updateMessageKind, UpdateMessageKind.error);
        expect(controller.state.checkingUpdates, isFalse);
      },
    );

    test(
      'checks again when an enabled app returns to the foreground',
      () async {
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
        await controller.handleAppResumed();

        expect(updateService.checks, hasLength(2));
        expect(updateService.checks, everyElement(isA<UpdateCheckCall>()));
        expect(updateService.checks.every((call) => !call.manual), isTrue);
      },
    );

    test(
      'contains release-launch failures and permits a successful retry',
      () async {
        final release = releaseFixture();
        final updateService = FakeUpdateService()
          ..result = AppUpdateResult(
            release: release,
            message: '2.0.0 is available',
          )
          ..queuedOpenErrors.add(StateError('platform launcher rejected URL'));
        final controller = AppController(
          settingsStore: FakeSettingsStore(
            const PersistedAppSettings(updateChecksEnabled: false),
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
        await controller.checkForUpdates(manual: true);

        expect(await controller.openAvailableRelease(), isFalse);
        expect(updateService.openAttempts, <ReleaseInfo>[release]);
        expect(updateService.opened, isEmpty);
        expect(
          controller.state.updateMessage,
          contains('platform launcher rejected URL'),
        );
        expect(controller.state.updateMessageKind, UpdateMessageKind.error);

        expect(await controller.openAvailableRelease(), isTrue);
        expect(updateService.openAttempts, <ReleaseInfo>[release, release]);
        expect(updateService.opened, <ReleaseInfo>[release]);
        expect(controller.state.updateMessage, isNull);
        expect(controller.state.updateMessageKind, isNull);
      },
    );
  });

  group('AppController server lifecycle policy', () {
    test(
      'forwards only actions justified by conclusive current state',
      () async {
        final stopped = enrolledServerFixture(
          id: 'server-stopped',
          name: 'Stopped',
          port: 3201,
          healthClassification: 'stopped',
          healthOk: false,
        );
        final running = enrolledServerFixture(
          id: 'server-running',
          name: 'Running',
          status: 'running',
          port: 3202,
          healthClassification: 'healthy',
          healthOk: true,
        );
        final inventory = emptyInventory(
          projects: <CoordinatorProject>[projectFixture()],
          servers: <CoordinatorServer>[stopped, running],
        );
        final service = FakeCoordinatorService(inventory: inventory);
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

        await controller.runServerAction(
          stopped,
          CoordinatorResourceAction.start,
        );
        await controller.runServerAction(
          running,
          CoordinatorResourceAction.restart,
        );
        await controller.runServerAction(
          running,
          CoordinatorResourceAction.stop,
        );

        expect(
          service.serverActions,
          <(CoordinatorServer, CoordinatorResourceAction)>[
            (stopped, CoordinatorResourceAction.start),
            (running, CoordinatorResourceAction.restart),
            (running, CoordinatorResourceAction.stop),
          ],
        );
      },
    );

    test(
      'blocks ambiguous lifecycle evidence before service dispatch',
      () async {
        final servers = <CoordinatorServer>[
          for (final status in <String>[
            'starting',
            'stopping',
            'failed',
            'unknown',
          ])
            enrolledServerFixture(
              id: 'server-$status',
              name: status,
              status: status,
              port: 3200,
            ),
          enrolledServerFixture(
            id: 'server-wrong-listener',
            name: 'wrong listener',
            status: 'running',
            port: 3201,
            healthClassification: 'wrong-listener',
          ),
        ];
        final inventory = emptyInventory(
          projects: <CoordinatorProject>[projectFixture()],
          servers: servers,
        );
        final service = FakeCoordinatorService(inventory: inventory);
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

        for (final server in servers) {
          await controller.runServerAction(
            server,
            CoordinatorResourceAction.restart,
          );
        }

        expect(service.serverActions, isEmpty);
        expect(
          controller.state.connectionError,
          contains('lifecycle state and listener identity are conclusive'),
        );
      },
    );

    test(
      'blocks a lookalike server outside the current object graph',
      () async {
        final committed = enrolledServerFixture(
          status: 'running',
          port: 3201,
          healthClassification: 'healthy',
          healthOk: true,
        );
        final lookalike = enrolledServerFixture(
          status: 'running',
          port: 3201,
          healthClassification: 'healthy',
          healthOk: true,
        );
        final inventory = emptyInventory(
          projects: <CoordinatorProject>[projectFixture()],
          servers: <CoordinatorServer>[committed],
        );
        final service = FakeCoordinatorService(inventory: inventory);
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

        await controller.runServerAction(
          lookalike,
          CoordinatorResourceAction.stop,
        );

        expect(service.serverActions, isEmpty);
        expect(
          controller.state.connectionError,
          contains('exact server from the current committed inventory'),
        );
      },
    );
  });

  group('AppController port leases', () {
    test(
      'forwards exact request, reveals lease, refreshes, and clears on release',
      () async {
        final project = projectFixture();
        final server = enrolledServerFixture();
        final lease = leaseFixture(port: 3555);
        final before = emptyInventory(
          projects: <CoordinatorProject>[project],
          servers: <CoordinatorServer>[server],
        );
        final afterLease = emptyInventory(
          projects: <CoordinatorProject>[project],
          servers: <CoordinatorServer>[server],
          leases: <CoordinatorLease>[lease],
        );
        final afterRelease = emptyInventory(
          projects: <CoordinatorProject>[project],
          servers: <CoordinatorServer>[server],
        );
        final service = FakeCoordinatorService(
          inventories: <CoordinatorInventory>[before, afterLease, afterRelease],
        )..leaseResponse = lease;
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

        final returned = await controller.leasePort(
          project: project,
          server: server,
          firstPort: 3500,
          lastPort: 3599,
          preferredPort: 3555,
          ttl: const Duration(hours: 2),
          purpose: 'desktop preview',
        );

        expect(returned, same(lease));
        expect(service.leaseCalls, hasLength(1));
        final call = service.leaseCalls.single;
        expect(call.project, same(project));
        expect(call.server, same(server));
        expect(call.firstPort, 3500);
        expect(call.lastPort, 3599);
        expect(call.preferredPort, 3555);
        expect(call.ttl, const Duration(hours: 2));
        expect(call.purpose, 'desktop preview');
        expect(controller.state.lastLease, same(lease));
        expect(controller.state.inventory, same(afterLease));
        expect(controller.state.actionKey, isNull);

        await controller.releasePort(lease);

        expect(service.releaseCalls, <CoordinatorLease>[lease]);
        expect(controller.state.lastLease, isNull);
        expect(controller.state.inventory, same(afterRelease));
        expect(controller.state.lastActionResult, same(service.actionResponse));
        expect(controller.state.lastActionLabel, 'Release port 3555');
        expect(controller.state.actionKey, isNull);
      },
    );

    test(
      'exposes a failed lease without replacing the current inventory',
      () async {
        final project = projectFixture();
        final server = enrolledServerFixture();
        final inventory = emptyInventory(
          projects: <CoordinatorProject>[project],
          servers: <CoordinatorServer>[server],
        );
        final service = FakeCoordinatorService(inventory: inventory)
          ..leaseError = StateError('no port available');
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

        final returned = await controller.leasePort(
          project: project,
          server: server,
          firstPort: 3000,
          lastPort: 3001,
        );

        expect(returned, isNull);
        expect(controller.state.inventory, same(inventory));
        expect(controller.state.lastLease, isNull);
        expect(controller.state.connectionError, contains('no port available'));
        expect(controller.state.actionKey, isNull);
      },
    );

    test(
      'rejects a server outside the selected committed project before service',
      () async {
        final project = projectFixture();
        final committedServer = enrolledServerFixture();
        final mismatchedServer = enrolledServerFixture(
          id: 'server-other',
          repoId: project.id,
          projectRoot: '/work/another-project',
        );
        final inventory = emptyInventory(
          projects: <CoordinatorProject>[project],
          servers: <CoordinatorServer>[committedServer, mismatchedServer],
        );
        final service = FakeCoordinatorService(inventory: inventory);
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

        final returned = await controller.leasePort(
          project: project,
          server: mismatchedServer,
          firstPort: 3000,
          lastPort: 3001,
        );

        expect(returned, isNull);
        expect(service.leaseCalls, isEmpty);
        expect(
          controller.state.connectionError,
          contains('exact enrolled server owned by the selected project'),
        );
        expect(controller.state.actionKey, isNull);
      },
    );

    test('rejects an ambiguous repository-scoped server name', () async {
      final project = projectFixture();
      final firstServer = enrolledServerFixture(name: 'API');
      final secondServer = enrolledServerFixture(id: 'server-2', name: 'API');
      final inventory = emptyInventory(
        projects: <CoordinatorProject>[project],
        servers: <CoordinatorServer>[firstServer, secondServer],
      );
      final service = FakeCoordinatorService(inventory: inventory);
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

      final returned = await controller.leasePort(
        project: project,
        server: firstServer,
        firstPort: 3000,
        lastPort: 3001,
      );

      expect(returned, isNull);
      expect(service.leaseCalls, isEmpty);
      expect(
        controller.state.connectionError,
        contains('exact enrolled server owned by the selected project'),
      );
    });

    test(
      'blocks retained and expired releases before service dispatch',
      () async {
        final released = leaseFixture(id: 'released', status: 'released');
        final failed = leaseFixture(id: 'failed', status: 'failed');
        final expired = leaseFixture(
          id: 'expired',
          expiresAt: DateTime.utc(2000),
        );
        final inventory = emptyInventory(
          projects: <CoordinatorProject>[projectFixture()],
          leases: <CoordinatorLease>[released, failed, expired],
        );
        final service = FakeCoordinatorService(inventory: inventory);
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

        await controller.releasePort(released);
        await controller.releasePort(failed);
        await controller.releasePort(expired);

        expect(service.releaseCalls, isEmpty);
        expect(
          controller.state.connectionError,
          contains('not active or has expired'),
        );
      },
    );
  });
}

final class _SequenceCoordinatorFactory
    implements AppCoordinatorServiceFactory {
  _SequenceCoordinatorFactory(this.services);

  final List<FakeCoordinatorService> services;
  var _index = 0;

  @override
  Future<AppCoordinatorService> connect({
    required StoredConnectionProfile profile,
    String? credential,
    bool interactive = false,
    void Function(CoordinatorConnectionProgress progress)? onProgress,
  }) async {
    return services[_index++];
  }
}
