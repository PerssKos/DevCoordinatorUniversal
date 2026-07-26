import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator/app/app.dart';
import 'package:devcoordinator/app/app_controller.dart';
import 'package:devcoordinator/app/app_services.dart';
import 'package:devcoordinator/app/app_state.dart';
import 'package:devcoordinator/core/storage/settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test(
    'cold native restore retains current meta session and inventory',
    () async {
      final profile = nativeProfile();
      final service = FakeNativeService();
      final factory = FakeNativeFactory(service);
      final tokenStore = FakeTokenStore(value: 'legacy-must-not-be-read');
      final controller = AppController(
        settingsStore: FakeSettingsStore(
          PersistedAppSettings(updateChecksEnabled: false, connection: profile),
        ),
        tokenStore: tokenStore,
        coordinatorFactory: factory,
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(factory.connectCalls, <bool>[false]);
      expect(tokenStore.readCount, 0);
      expect(controller.state.nativeInventory, same(service.inventory));
      expect(controller.state.nativeMeta, same(service.nativeMeta));
      expect(controller.state.nativeSession, same(service.nativeSession));
      expect(controller.state.connectionPhase, ConnectionPhase.connected);
      expect(controller.state.isConnected, isTrue);
    },
  );

  test(
    'failed active revocation retains profile and retries before close',
    () async {
      final profile = nativeProfile();
      final service = FakeNativeService()
        ..revokeResults.addAll(<Object?>[
          StateError('revocation offline'),
          null,
        ]);
      final settingsStore = FakeSettingsStore(
        PersistedAppSettings(updateChecksEnabled: false, connection: profile),
      );
      final controller = AppController(
        settingsStore: settingsStore,
        tokenStore: FakeTokenStore(),
        coordinatorFactory: FakeNativeFactory(service),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.disconnect();

      expect(controller.state.settings.connection, same(profile));
      expect(controller.state.connectionPhase, ConnectionPhase.revoked);
      expect(controller.state.availability, ConnectionAvailability.unavailable);
      expect(service.closeCount, 0);
      expect(settingsStore.value.connection, same(profile));

      await controller.disconnect();

      expect(controller.state.settings.connection, isNull);
      expect(controller.state.connectionPhase, ConnectionPhase.disconnected);
      expect(service.revokeCount, 2);
      expect(service.closeCount, 1);
      expect(settingsStore.value.connection, isNull);
    },
  );

  test(
    'failed native revocation survives restart and never reconnects',
    () async {
      final profile = nativeProfile();
      final events = <String>[];
      final firstService = FakeNativeService()
        ..revokeResults.add(StateError('secure revocation fence unavailable'));
      final settingsStore = FakeSettingsStore(
        PersistedAppSettings(updateChecksEnabled: false, connection: profile),
        events: events,
      );
      final firstController = AppController(
        settingsStore: settingsStore,
        tokenStore: FakeTokenStore(),
        coordinatorFactory: FakeNativeFactory(firstService),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      await firstController.initialize();
      events.clear();

      await firstController.disconnect();

      expect(firstService.revokeCount, 1);
      expect(settingsStore.value.connection, same(profile));
      expect(settingsStore.value.credentialCleanupPending, isTrue);
      expect(firstController.state.settings.credentialCleanupPending, isTrue);
      expect(events, <String>['settings.cleanupMarker.true']);
      firstController.dispose();

      final restartedFactory = FakeNativeFactory(FakeNativeService())
        ..storedRevokeResults.addAll(<Object?>[
          StateError('revocation endpoint offline'),
          null,
        ]);
      final restartedController = AppController(
        settingsStore: settingsStore,
        tokenStore: FakeTokenStore(),
        coordinatorFactory: restartedFactory,
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(restartedController.dispose);
      events.clear();

      await restartedController.initialize();

      expect(restartedFactory.connectCalls, isEmpty);
      expect(restartedFactory.storedRevokeCount, 1);
      expect(settingsStore.value.connection, same(profile));
      expect(settingsStore.value.credentialCleanupPending, isTrue);
      expect(
        restartedController.state.connectionPhase,
        ConnectionPhase.revoked,
      );

      events.clear();
      await restartedController.disconnect();

      expect(restartedFactory.connectCalls, isEmpty);
      expect(restartedFactory.storedRevokeCount, 2);
      expect(settingsStore.value.connection, isNull);
      expect(settingsStore.value.credentialCleanupPending, isFalse);
      expect(
        events.indexOf('settings.write'),
        lessThan(events.indexOf('settings.cleanupMarker.false')),
      );
      expect(
        restartedController.state.connectionPhase,
        ConnectionPhase.disconnected,
      );
    },
  );

  test(
    'native disconnect dispatches nothing when its durable marker fails',
    () async {
      final profile = nativeProfile();
      final service = FakeNativeService();
      final settingsStore = FakeSettingsStore(
        PersistedAppSettings(updateChecksEnabled: false, connection: profile),
      )..cleanupMarkerError = StateError('preferences unavailable');
      final controller = AppController(
        settingsStore: settingsStore,
        tokenStore: FakeTokenStore(),
        coordinatorFactory: FakeNativeFactory(service),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.disconnect();

      expect(service.revokeCount, 0);
      expect(service.closeCount, 0);
      expect(settingsStore.value.connection, same(profile));
      expect(settingsStore.value.credentialCleanupPending, isFalse);
      expect(controller.state.settings.connection, same(profile));
      expect(controller.state.connectionPhase, ConnectionPhase.connected);
      expect(controller.state.availability, ConnectionAvailability.available);
      expect(
        controller.state.connectionError,
        contains('preferences unavailable'),
      );
    },
  );

  test(
    'disconnect revokes a stored session when restore never connected',
    () async {
      final profile = nativeProfile();
      final service = FakeNativeService();
      final factory = FakeNativeFactory(service)
        ..connectError = StateError('gateway offline')
        ..storedRevokeResults.addAll(<Object?>[
          StateError('revocation offline'),
          null,
        ]);
      final settingsStore = FakeSettingsStore(
        PersistedAppSettings(updateChecksEnabled: false, connection: profile),
      );
      final controller = AppController(
        settingsStore: settingsStore,
        tokenStore: FakeTokenStore(),
        coordinatorFactory: factory,
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.state.isConnected, isFalse);

      await controller.disconnect();

      expect(controller.state.settings.connection, same(profile));
      expect(controller.state.connectionPhase, ConnectionPhase.revoked);
      expect(factory.storedRevokeCount, 1);

      await controller.disconnect();

      expect(controller.state.settings.connection, isNull);
      expect(factory.storedRevokeCount, 2);
      expect(settingsStore.value.connection, isNull);
    },
  );

  for (final terminal in <NativeGatewayOperation>[
    nativeOperationFixture(
      status: NativeGatewayOperationStatus.failed,
      targetStatus: NativeGatewayOperationTargetStatus.failed,
    ),
    nativeOperationFixture(
      status: NativeGatewayOperationStatus.partial,
      partial: true,
      targetStatus: NativeGatewayOperationTargetStatus.succeeded,
    ),
    nativeOperationFixture(
      status: NativeGatewayOperationStatus.needsAttention,
      needsAttention: true,
      targetStatus: NativeGatewayOperationTargetStatus.failed,
    ),
  ]) {
    test(
      'terminal ${terminal.status.name} action stays visible and fences mutations',
      () async {
        final project = NativeGatewayProject(
          id: 'project-1',
          displayName: 'Project One',
          state: NativeGatewayResourceState.running,
          allowedActions: const <NativeGatewayResourceAction>[
            NativeGatewayResourceAction.restart,
          ],
        );
        final resource = nativeResource('resource-1', project.id);
        final service =
            FakeNativeService(
                inventory: NativeGatewayInventory(
                  revision: 'revision-1',
                  observedAt: DateTime.utc(2026),
                  partial: false,
                  projects: <NativeGatewayProject>[project],
                  resources: <NativeGatewayResource>[resource],
                  leases: const <NativeGatewayPortLease>[],
                  blockers: const <NativeGatewayBlocker>[],
                ),
              )
              ..nativeActionGate = const NativeActionGate.allowed()
              ..nativeActionResults.add(terminal);
        final controller = AppController(
          settingsStore: FakeSettingsStore(
            PersistedAppSettings(
              updateChecksEnabled: false,
              connection: nativeProfile(),
            ),
          ),
          tokenStore: FakeTokenStore(),
          coordinatorFactory: FakeNativeFactory(service),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final result = await controller.runNativeResourceAction(
          resource,
          NativeGatewayResourceAction.restart,
        );

        expect(result, isNull);
        expect(controller.state.lastNativeOperation, same(terminal));
        expect(controller.state.connectionError, isNotNull);
        expect(controller.state.availability, ConnectionAvailability.stale);
        expect(controller.state.connectionPhase, ConnectionPhase.stale);
        expect(controller.state.canMutate, isFalse);
      },
    );
  }

  test(
    'an inconclusive native mutation keeps the committed view fenced',
    () async {
      final project = NativeGatewayProject(
        id: 'project-1',
        displayName: 'Project One',
        state: NativeGatewayResourceState.running,
        allowedActions: const <NativeGatewayResourceAction>[
          NativeGatewayResourceAction.restart,
        ],
      );
      final resource = nativeResource('resource-1', project.id);
      final service =
          FakeNativeService(
              inventory: NativeGatewayInventory(
                revision: 'revision-1',
                observedAt: DateTime.utc(2026),
                partial: false,
                projects: <NativeGatewayProject>[project],
                resources: <NativeGatewayResource>[resource],
                leases: const <NativeGatewayPortLease>[],
                blockers: const <NativeGatewayBlocker>[],
              ),
            )
            ..nativeActionGate = const NativeActionGate.allowed()
            ..nativeActionResults.add(
              const CoordinatorMutationOutcomeUnknownException(
                method: 'POST',
                path: '/resources/{resourceId}/actions/restart',
                timeout: Duration(seconds: 15),
              ),
            );
      final controller = AppController(
        settingsStore: FakeSettingsStore(
          PersistedAppSettings(
            updateChecksEnabled: false,
            connection: nativeProfile(),
          ),
        ),
        tokenStore: FakeTokenStore(),
        coordinatorFactory: FakeNativeFactory(service),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final result = await controller.runNativeResourceAction(
        resource,
        NativeGatewayResourceAction.restart,
      );

      expect(result, isNull);
      expect(controller.state.availability, ConnectionAvailability.stale);
      expect(controller.state.connectionPhase, ConnectionPhase.stale);
      expect(controller.state.connectionError, contains('outcome is unknown'));
      expect(controller.state.canMutate, isFalse);
    },
  );

  test(
    'native event history deduplicates overlapping page boundaries and stops at end',
    () async {
      final first = nativeEvent(1);
      final boundary = nativeEvent(2);
      final last = nativeEvent(3);
      final service = FakeNativeService()
        ..nativeEventResults.addAll(<Object>[
          nativeEventPage(
            <NativeGatewayEvent>[first, boundary],
            nextCursor: 'opaque-page-2',
            hasMore: true,
          ),
          nativeEventPage(<NativeGatewayEvent>[boundary, last]),
        ]);
      final controller = nativeController(service);
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.loadNativeEvents();

      expect(service.nativeEventAfterCalls, <String?>[null]);
      expect(controller.state.nativeEvents.map((event) => event.id), <String>[
        'event-1',
        'event-2',
      ]);
      expect(controller.state.nativeEventsCursor, 'opaque-page-2');
      expect(controller.state.nativeEventsHasMore, isTrue);

      await controller.loadNativeEvents();

      expect(service.nativeEventAfterCalls, <String?>[null, 'opaque-page-2']);
      expect(controller.state.nativeEvents.map((event) => event.id), <String>[
        'event-1',
        'event-2',
        'event-3',
      ]);
      expect(controller.state.nativeEventsCursor, isNull);
      expect(controller.state.nativeEventsHasMore, isFalse);
      expect(controller.state.nativeEventsError, isNull);

      await controller.loadNativeEvents();
      expect(service.nativeEventAfterCalls, <String?>[null, 'opaque-page-2']);
    },
  );

  test(
    'failed native event refresh retains history and retries from the beginning',
    () async {
      final retained = nativeEvent(1);
      final replacement = nativeEvent(9);
      final service = FakeNativeService()
        ..nativeEventResults.addAll(<Object>[
          nativeEventPage(
            <NativeGatewayEvent>[retained],
            nextCursor: 'retained-cursor',
            hasMore: true,
          ),
          const CoordinatorProtocolException(
            'Event history is temporarily unavailable.',
          ),
          nativeEventPage(<NativeGatewayEvent>[replacement]),
        ]);
      final controller = nativeController(service);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.loadNativeEvents();

      await controller.loadNativeEvents(refresh: true);

      expect(service.nativeEventAfterCalls, <String?>[null, null]);
      expect(controller.state.nativeEvents, <NativeGatewayEvent>[retained]);
      expect(controller.state.nativeEventsCursor, 'retained-cursor');
      expect(controller.state.nativeEventsHasMore, isTrue);
      expect(
        controller.state.nativeEventsError,
        'Event history is temporarily unavailable.',
      );

      await controller.loadNativeEvents(refresh: true);

      expect(service.nativeEventAfterCalls, <String?>[null, null, null]);
      expect(controller.state.nativeEvents, <NativeGatewayEvent>[replacement]);
      expect(controller.state.nativeEventsCursor, isNull);
      expect(controller.state.nativeEventsHasMore, isFalse);
      expect(controller.state.nativeEventsError, isNull);
    },
  );

  test(
    'non-advancing native event cursor retains the committed page for retry',
    () async {
      final retained = nativeEvent(1);
      final rejected = nativeEvent(2);
      final service = FakeNativeService()
        ..nativeEventResults.addAll(<Object>[
          nativeEventPage(
            <NativeGatewayEvent>[retained],
            nextCursor: 'same-cursor',
            hasMore: true,
          ),
          nativeEventPage(
            <NativeGatewayEvent>[rejected],
            nextCursor: 'same-cursor',
            hasMore: true,
          ),
          nativeEventPage(<NativeGatewayEvent>[rejected]),
        ]);
      final controller = nativeController(service);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.loadNativeEvents();

      await controller.loadNativeEvents();

      expect(service.nativeEventAfterCalls, <String?>[null, 'same-cursor']);
      expect(controller.state.nativeEvents, <NativeGatewayEvent>[retained]);
      expect(controller.state.nativeEventsCursor, 'same-cursor');
      expect(controller.state.nativeEventsHasMore, isTrue);
      expect(
        controller.state.nativeEventsError,
        'The event cursor did not advance.',
      );

      await controller.loadNativeEvents();

      expect(service.nativeEventAfterCalls, <String?>[
        null,
        'same-cursor',
        'same-cursor',
      ]);
      expect(controller.state.nativeEvents.map((event) => event.id), <String>[
        'event-1',
        'event-2',
      ]);
      expect(controller.state.nativeEventsCursor, isNull);
      expect(controller.state.nativeEventsHasMore, isFalse);
      expect(controller.state.nativeEventsError, isNull);
    },
  );

  for (final viewport in <({String name, Size size})>[
    (name: 'narrow', size: const Size(390, 844)),
    (name: 'wide', size: const Size(1440, 900)),
  ]) {
    testWidgets(
      'long ${viewport.name} native event history exposes error retry and end',
      (tester) async {
        tester.view
          ..physicalSize = viewport.size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final firstPage = List<NativeGatewayEvent>.generate(
          24,
          nativeEvent,
          growable: false,
        );
        final secondPage = <NativeGatewayEvent>[
          firstPage.last,
          ...List<NativeGatewayEvent>.generate(
            16,
            (index) => nativeEvent(index + 24),
            growable: false,
          ),
        ];
        final service = FakeNativeService()
          ..nativeEventResults.addAll(<Object>[
            nativeEventPage(
              firstPage,
              nextCursor: 'long-page-2',
              hasMore: true,
            ),
            const CoordinatorProtocolException(
              'Event page temporarily unavailable.',
            ),
            nativeEventPage(secondPage),
          ]);
        final controller = nativeController(service);
        addTearDown(controller.dispose);
        await controller.initialize();
        controller.selectSection(AppSection.events);

        await tester.pumpWidget(DevCoordinatorApp(controller: controller));
        await tester.pumpAndSettle();

        expect(find.text('Event history'), findsOne);
        expect(find.byKey(const ValueKey<String>('native-events')), findsOne);
        expect(controller.state.nativeEvents, hasLength(24));
        expect(service.nativeEventAfterCalls, <String?>[null]);

        final historyScrollable = find.descendant(
          of: find.byKey(const ValueKey<String>('native-events')),
          matching: find.byType(Scrollable),
        );
        expect(historyScrollable, findsOne);
        await tester.scrollUntilVisible(
          find.text('Load more'),
          500,
          scrollable: historyScrollable,
        );
        await tester.drag(historyScrollable, const Offset(0, -160));
        await tester.pumpAndSettle();
        expect(find.text('Load more').hitTestable(), findsOne);
        await tester.tap(find.text('Load more').hitTestable());
        await tester.pumpAndSettle();

        expect(find.text('Event page temporarily unavailable.'), findsOne);
        expect(controller.state.nativeEvents, hasLength(24));
        expect(controller.state.nativeEventsCursor, 'long-page-2');
        expect(controller.state.nativeEventsHasMore, isTrue);
        await tester.scrollUntilVisible(
          find.text('Load more'),
          500,
          scrollable: historyScrollable,
        );
        await tester.drag(historyScrollable, const Offset(0, -160));
        await tester.pumpAndSettle();
        expect(find.text('Load more').hitTestable(), findsOne);

        await tester.tap(find.text('Load more').hitTestable());
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(eventMessage(39)),
          500,
          scrollable: historyScrollable,
        );

        expect(service.nativeEventAfterCalls, <String?>[
          null,
          'long-page-2',
          'long-page-2',
        ]);
        expect(controller.state.nativeEvents, hasLength(40));
        expect(controller.state.nativeEventsCursor, isNull);
        expect(controller.state.nativeEventsHasMore, isFalse);
        expect(controller.state.nativeEventsError, isNull);
        expect(find.text(eventMessage(39)), findsOne);
        expect(find.text('Load more'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Russian native resources disambiguate same-name rows by project',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('ru'),
      ];
      try {
        final firstProject = NativeGatewayProject(
          id: 'project-a',
          displayName: 'Альфа',
          state: NativeGatewayResourceState.running,
          allowedActions: const <NativeGatewayResourceAction>[],
        );
        final secondProject = NativeGatewayProject(
          id: 'project-b',
          displayName: 'Бета',
          state: NativeGatewayResourceState.running,
          allowedActions: const <NativeGatewayResourceAction>[],
        );
        final service = FakeNativeService(
          inventory: NativeGatewayInventory(
            revision: 'revision-collision',
            observedAt: DateTime.utc(2026),
            partial: false,
            projects: <NativeGatewayProject>[firstProject, secondProject],
            resources: <NativeGatewayResource>[
              nativeResource('server-a', firstProject.id),
              nativeResource('server-b', secondProject.id),
            ],
            leases: <NativeGatewayPortLease>[
              NativeGatewayPortLease(
                id: 'lease-expired',
                projectId: firstProject.id,
                serverResourceId: 'server-a',
                port: 30001,
                purpose: 'Предпросмотр',
                status: NativeGatewayPortLeaseStatus.active,
                releasable: true,
                expiresAt: DateTime.utc(2025),
              ),
            ],
            blockers: const <NativeGatewayBlocker>[],
          ),
        );
        final controller = AppController(
          settingsStore: FakeSettingsStore(
            PersistedAppSettings(
              updateChecksEnabled: false,
              connection: nativeProfile(),
            ),
          ),
          tokenStore: FakeTokenStore(),
          coordinatorFactory: FakeNativeFactory(service),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        controller.selectSection(AppSection.servers);

        await tester.pumpWidget(DevCoordinatorApp(controller: controller));
        await tester.pumpAndSettle();

        expect(find.text('Одинаковый сервер'), findsNWidgets(2));
        expect(find.text('Проект: Альфа'), findsOne);
        expect(find.text('Проект: Бета'), findsOne);
        expect(find.text('Запущен'), findsNWidgets(2));
        expect(find.text('Перезапустить'), findsNWidgets(2));
        expect(find.text('restart'), findsNothing);

        controller.selectSection(AppSection.ports);
        await tester.pumpAndSettle();
        expect(find.text('Истекла'), findsOne);
        expect(find.text('Активна'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.binding.platformDispatcher.clearLocalesTestValue();
      }
    },
  );
}

StoredConnectionProfile nativeProfile() => const StoredConnectionProfile(
  kind: StoredConnectionKind.nativeGatewayV2,
  baseUrl: 'https://console.classified.guru/api/v2',
  label: 'DevCoordinator',
);

NativeGatewayResource nativeResource(String id, String projectId) =>
    NativeGatewayResource(
      id: id,
      projectId: projectId,
      kind: NativeGatewayResourceKind.server,
      displayName: 'Одинаковый сервер',
      state: NativeGatewayResourceState.running,
      allowedActions: const <NativeGatewayResourceAction>[
        NativeGatewayResourceAction.restart,
      ],
      blockers: const <NativeGatewayBlocker>[],
    );

AppController nativeController(FakeNativeService service) => AppController(
  settingsStore: FakeSettingsStore(
    PersistedAppSettings(
      updateChecksEnabled: false,
      connection: nativeProfile(),
    ),
  ),
  tokenStore: FakeTokenStore(),
  coordinatorFactory: FakeNativeFactory(service),
  updateService: FakeUpdateService(),
  packageInfoLoader: packageInfoFixture,
);

String eventMessage(int index) =>
    'Event ${index.toString().padLeft(2, '0')} — retained server history';

NativeGatewayEvent nativeEvent(int index) => NativeGatewayEvent(
  id: 'event-$index',
  kind: 'server.lifecycle',
  code: 'event_$index',
  message: eventMessage(index),
  occurredAt: DateTime.utc(2026, 7, 26, 12).add(Duration(minutes: index)),
  projectId: 'project-1',
  resourceId: 'resource-1',
);

NativeGatewayEventPage nativeEventPage(
  List<NativeGatewayEvent> events, {
  String? nextCursor,
  bool hasMore = false,
}) => NativeGatewayEventPage(
  events: events,
  nextCursor: nextCursor,
  hasMore: hasMore,
);

NativeGatewayInventory _defaultInventory() => NativeGatewayInventory(
  revision: 'revision-1',
  observedAt: DateTime.utc(2026),
  partial: false,
  projects: <NativeGatewayProject>[
    NativeGatewayProject(
      id: 'project-1',
      displayName: 'Project One',
      state: NativeGatewayResourceState.running,
      allowedActions: const <NativeGatewayResourceAction>[],
    ),
  ],
  resources: const <NativeGatewayResource>[],
  leases: const <NativeGatewayPortLease>[],
  blockers: const <NativeGatewayBlocker>[],
);

final class FakeNativeFactory
    implements AppCoordinatorServiceFactory, NativeStoredSessionRevoker {
  FakeNativeFactory(this.service);

  final FakeNativeService service;
  final List<bool> connectCalls = <bool>[];
  final List<Object?> storedRevokeResults = <Object?>[];
  Object? connectError;
  int storedRevokeCount = 0;

  @override
  Future<AppCoordinatorService> connect({
    required StoredConnectionProfile profile,
    String? credential,
    bool interactive = false,
    void Function(CoordinatorConnectionProgress progress)? onProgress,
  }) async {
    connectCalls.add(interactive);
    final error = connectError;
    if (error != null) throw error;
    return service;
  }

  @override
  Future<void> revokeStoredNativeSession(
    StoredConnectionProfile profile,
  ) async {
    final index = storedRevokeCount++;
    final result = index < storedRevokeResults.length
        ? storedRevokeResults[index]
        : null;
    if (result != null) throw result;
  }
}

final class FakeNativeService implements NativeAppCoordinatorService {
  FakeNativeService({NativeGatewayInventory? inventory})
    : inventory = inventory ?? _defaultInventory();

  final List<Object?> revokeResults = <Object?>[];
  final List<Object> nativeActionResults = <Object>[];
  final List<Object> nativeEventResults = <Object>[];
  final List<String?> nativeEventAfterCalls = <String?>[];
  NativeActionGate nativeActionGate = const NativeActionGate.blocked('blocked');
  int revokeCount = 0;
  int closeCount = 0;
  int nativeActionCount = 0;
  int nativeEventCount = 0;

  final NativeGatewayInventory inventory;

  @override
  final NativeGatewayMeta nativeMeta = NativeGatewayMeta(
    contractVersion: '2.0.0',
    serverVersion: '2.0.0',
    minimumClientVersion: '0.2.0',
    issuer: Uri.parse('https://console.classified.guru'),
    authorizationEndpoint: Uri.parse(
      'https://console.classified.guru/oauth/authorize',
    ),
    tokenEndpoint: Uri.parse('https://console.classified.guru/oauth/token'),
    revocationEndpoint: Uri.parse(
      'https://console.classified.guru/oauth/revoke',
    ),
    publicClientId: 'io.github.holyglory.devcoordinator',
    pkceMethods: const <NativeGatewayPkceMethod>{NativeGatewayPkceMethod.s256},
    capabilities: NativeGatewayCapabilities(const <NativeGatewayCapability>{
      NativeGatewayCapability.inventoryRead,
      NativeGatewayCapability.eventsRead,
    }),
  );

  @override
  final NativeGatewaySession nativeSession = NativeGatewaySession(
    userId: 'user-1',
    email: 'user@example.com',
    deviceSessionId: 'device-1',
    roles: const <NativeGatewaySessionRole>{
      NativeGatewaySessionRole.invitedOperator,
    },
    scopes: const <String>{'inventory:read'},
    grants: const <NativeGatewayGrant>[],
    expiresAt: DateTime.utc(2030),
  );

  @override
  NativeGatewayInventory? get currentNativeInventory => inventory;

  @override
  NativeGatewayEntityTag? get currentNativeEntityTag =>
      NativeGatewayEntityTag.parse('"revision-1"');

  @override
  Future<NativeGatewayInventory> loadNativeInventory() async => inventory;

  @override
  Future<void> revokeNativeSession() async {
    final index = revokeCount++;
    final result = index < revokeResults.length ? revokeResults[index] : null;
    if (result != null) throw result;
  }

  @override
  bool supports(CoordinatorCapability capability) =>
      capability == CoordinatorCapability.inventoryRead ||
      capability == CoordinatorCapability.eventsRead;

  @override
  NativeActionGate canActOnNativeProject(
    NativeGatewayProject project,
    NativeGatewayResourceAction action,
  ) => const NativeActionGate.blocked('blocked');

  @override
  NativeActionGate canActOnNativeResource(
    NativeGatewayResource resource,
    NativeGatewayResourceAction action,
  ) => nativeActionGate;

  @override
  NativeActionGate canManageNativeLease({
    required String projectId,
    String? leaseId,
  }) => const NativeActionGate.blocked('blocked');

  @override
  NativeActionGate canReadNativeLogs(NativeGatewayResource resource) =>
      const NativeActionGate.blocked('blocked');

  @override
  Future<NativeGatewayOperation> actOnNativeProject(
    NativeGatewayProject project,
    NativeGatewayResourceAction action, {
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<NativeGatewayOperation> actOnNativeResource(
    NativeGatewayResource resource,
    NativeGatewayResourceAction action, {
    String? reason,
  }) async {
    final result = nativeActionResults[nativeActionCount++];
    if (result is Exception) throw result;
    return result as NativeGatewayOperation;
  }

  @override
  Future<NativeGatewayPortLease> leaseNativePort({
    required NativeGatewayProject project,
    required NativeGatewayResource server,
    required int firstPort,
    required int lastPort,
    required String purpose,
    int? preferredPort,
    Duration? ttl,
  }) => throw UnimplementedError();

  @override
  Future<NativeGatewayEventPage> loadNativeEvents({
    String? after,
    int limit = 100,
  }) async {
    nativeEventAfterCalls.add(after);
    if (nativeEventCount >= nativeEventResults.length) {
      throw StateError('No native event result was queued.');
    }
    final result = nativeEventResults[nativeEventCount++];
    if (result is NativeGatewayEventPage) return result;
    throw result;
  }

  @override
  Future<NativeGatewayLogPage> readNativeLogs(
    NativeGatewayResource resource, {
    String? cursor,
    int limit = 200,
  }) => throw UnimplementedError();

  @override
  Future<void> releaseNativePort(NativeGatewayPortLease lease) =>
      throw UnimplementedError();

  @override
  Future<CoordinatorInventory> loadInventory() => throw UnimplementedError();

  @override
  Future<CoordinatorActionResult> actOnContainer(
    CoordinatorContainer container,
    CoordinatorResourceAction action,
  ) => throw UnimplementedError();

  @override
  Future<CoordinatorActionResult> actOnProject(
    CoordinatorProject project,
    CoordinatorProjectAction action,
  ) => throw UnimplementedError();

  @override
  Future<CoordinatorActionResult> actOnServer(
    CoordinatorServer server,
    CoordinatorResourceAction action,
  ) => throw UnimplementedError();

  @override
  Future<CoordinatorLease> leasePort({
    required CoordinatorProject project,
    required CoordinatorServer server,
    required int firstPort,
    required int lastPort,
    int? preferredPort,
    Duration? ttl,
    String? purpose,
  }) => throw UnimplementedError();

  @override
  Future<CoordinatorLogResult> readContainerLogs(
    CoordinatorContainer container, {
    int tail = 200,
  }) => throw UnimplementedError();

  @override
  Future<CoordinatorLogResult> readServerLogs(
    CoordinatorServer server, {
    int tail = 200,
  }) => throw UnimplementedError();

  @override
  Future<CoordinatorActionResult> releasePort(CoordinatorLease lease) =>
      throw UnimplementedError();

  @override
  void close() {
    closeCount += 1;
  }
}

NativeGatewayOperation nativeOperationFixture({
  required NativeGatewayOperationStatus status,
  required NativeGatewayOperationTargetStatus targetStatus,
  bool partial = false,
  bool needsAttention = false,
}) => NativeGatewayOperation(
  id: '123e4567-e89b-42d3-a456-426614174000',
  status: status,
  partial: partial,
  needsAttention: needsAttention,
  startedAt: DateTime.utc(2026),
  finishedAt: DateTime.utc(2026),
  results: <NativeGatewayOperationTargetResult>[
    NativeGatewayOperationTargetResult(
      targetId: 'resource-1',
      targetKind: NativeGatewayOperationTargetKind.server,
      status: targetStatus,
      message: 'Terminal result',
      evidenceIds: const <String>[],
    ),
  ],
  errors: const <NativeGatewayProblem>[],
);
