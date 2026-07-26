import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator/core/auth/native_authorization_router.dart';
import 'package:devcoordinator/core/auth/native_oauth.dart';
import 'package:devcoordinator/core/auth/native_oauth_session_manager.dart';
import 'package:devcoordinator/core/auth/native_session_store.dart';
import 'package:devcoordinator/core/coordinator/native_coordinator_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

void main() {
  test(
    'action gate intersects capability scope grant action and ETag',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id),
        ],
        inventory: inventoryFixture(project: project, resource: resource),
      );
      final service = serviceFixture(core);

      await service.loadNativeInventory();

      expect(
        service
            .canActOnNativeResource(
              resource,
              NativeGatewayResourceAction.restart,
            )
            .allowed,
        isTrue,
      );
      expect(
        service
            .canActOnNativeResource(resource, NativeGatewayResourceAction.start)
            .allowed,
        isFalse,
      );

      final clone = resourceFixture(projectId: project.id);
      expect(
        service
            .canActOnNativeResource(clone, NativeGatewayResourceAction.restart)
            .allowed,
        isFalse,
      );
    },
  );

  test(
    'authoritative refresh atomically shrinks live session grants',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final full = sessionFixture(resourceId: resource.id);
      final shrunk = sessionFixture(
        resourceId: resource.id,
        scopes: const <String>{'inventory:read'},
        permissions: const <String>{},
      );
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[full, shrunk],
        inventory: inventoryFixture(project: project, resource: resource),
      );
      final service = serviceFixture(core);

      await service.loadNativeInventory();
      expect(
        service
            .canActOnNativeResource(
              resource,
              NativeGatewayResourceAction.restart,
            )
            .allowed,
        isTrue,
      );

      await service.loadNativeInventory();

      expect(service.nativeSession.scopes, const <String>{'inventory:read'});
      expect(
        service
            .canActOnNativeResource(
              resource,
              NativeGatewayResourceAction.restart,
            )
            .allowed,
        isFalse,
      );
    },
  );

  test('unknown action outcome replays once with the exact same key', () async {
    final project = projectFixture();
    final resource = resourceFixture(projectId: project.id);
    final core = FakeNativeCore(
      sessions: <NativeGatewaySession>[sessionFixture(resourceId: resource.id)],
      inventory: inventoryFixture(project: project, resource: resource),
      actionResults: <Object>[
        const CoordinatorMutationOutcomeUnknownException(
          method: 'POST',
          path: '/resources/id/actions/restart',
          timeout: Duration(seconds: 15),
        ),
        operationFixture(),
      ],
    );
    final service = serviceFixture(core);
    await service.loadNativeInventory();

    final operation = await service.actOnNativeResource(
      resource,
      NativeGatewayResourceAction.restart,
    );

    expect(operation.isSuccessful, isTrue);
    expect(core.resourceActionKeys, hasLength(2));
    expect(core.resourceActionKeys[0], core.resourceActionKeys[1]);
  });

  test(
    'two inconclusive action responses keep the exact replay key and fail closed',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id),
        ],
        inventory: inventoryFixture(project: project, resource: resource),
        actionResults: <Object>[unknownMutation(), unknownMutation()],
      );
      final service = serviceFixture(core);
      await service.loadNativeInventory();

      await expectLater(
        service.actOnNativeResource(
          resource,
          NativeGatewayResourceAction.restart,
        ),
        throwsA(isA<CoordinatorMutationOutcomeUnknownException>()),
      );

      expect(core.resourceActionKeys, hasLength(2));
      expect(core.resourceActionKeys[0], core.resourceActionKeys[1]);
      expect(core.inventoryReads, 2);
    },
  );

  test('a determinate first-response 4xx is never replayed', () async {
    final project = projectFixture();
    final resource = resourceFixture(projectId: project.id);
    final problem = NativeGatewayProblemException(
      httpStatus: 412,
      problem: NativeGatewayProblem(
        type: 'https://console.classified.guru/problems/precondition',
        title: 'Precondition failed',
        status: 412,
        code: 'precondition_failed',
        blockers: const <NativeGatewayBlocker>[],
        extensions: const <String, Object?>{},
      ),
    );
    final core = FakeNativeCore(
      sessions: <NativeGatewaySession>[sessionFixture(resourceId: resource.id)],
      inventory: inventoryFixture(project: project, resource: resource),
      actionResults: <Object>[problem],
    );
    final service = serviceFixture(core);
    await service.loadNativeInventory();

    await expectLater(
      service.actOnNativeResource(
        resource,
        NativeGatewayResourceAction.restart,
      ),
      throwsA(same(problem)),
    );

    expect(core.resourceActionKeys, hasLength(1));
    expect(core.operationReads, isEmpty);
  });

  for (final terminal in <NativeGatewayOperation>[
    operationFixture(
      status: NativeGatewayOperationStatus.failed,
      targetStatus: NativeGatewayOperationTargetStatus.failed,
    ),
    operationFixture(
      status: NativeGatewayOperationStatus.partial,
      partial: true,
      targetStatus: NativeGatewayOperationTargetStatus.succeeded,
    ),
    operationFixture(
      status: NativeGatewayOperationStatus.needsAttention,
      needsAttention: true,
      targetStatus: NativeGatewayOperationTargetStatus.failed,
    ),
  ]) {
    test(
      'terminal ${terminal.status.name} action is retained as failure',
      () async {
        final project = projectFixture();
        final resource = resourceFixture(projectId: project.id);
        final core = FakeNativeCore(
          sessions: <NativeGatewaySession>[
            sessionFixture(resourceId: resource.id),
          ],
          inventory: inventoryFixture(project: project, resource: resource),
          actionResults: <Object>[terminal],
        );
        final service = serviceFixture(core);
        await service.loadNativeInventory();

        await expectLater(
          service.actOnNativeResource(
            resource,
            NativeGatewayResourceAction.restart,
          ),
          throwsA(
            isA<NativeOperationFailedException>().having(
              (error) => error.operation,
              'operation',
              same(terminal),
            ),
          ),
        );

        expect(core.inventoryReads, 2);
      },
    );
  }

  test('terminal action result must bind the exact requested target', () async {
    final project = projectFixture();
    final resource = resourceFixture(projectId: project.id);
    final core = FakeNativeCore(
      sessions: <NativeGatewaySession>[sessionFixture(resourceId: resource.id)],
      inventory: inventoryFixture(project: project, resource: resource),
      actionResults: <Object>[operationFixture(targetId: 'other-resource')],
    );
    final service = serviceFixture(core);
    await service.loadNativeInventory();

    await expectLater(
      service.actOnNativeResource(
        resource,
        NativeGatewayResourceAction.restart,
      ),
      throwsA(isA<CoordinatorMutationOutcomeUnknownException>()),
    );

    expect(core.inventoryReads, 1);
  });

  test('polling rejects a snapshot for another operation id', () async {
    const otherOperationId = '223e4567-e89b-42d3-a456-426614174000';
    final project = projectFixture();
    final resource = resourceFixture(projectId: project.id);
    final core = FakeNativeCore(
      sessions: <NativeGatewaySession>[sessionFixture(resourceId: resource.id)],
      inventory: inventoryFixture(project: project, resource: resource),
      actionResults: <Object>[
        operationFixture(status: NativeGatewayOperationStatus.running),
      ],
      operationResults: <Object>[
        operationFixture(operationId: otherOperationId),
      ],
    );
    final service = serviceFixture(core);
    await service.loadNativeInventory();

    await expectLater(
      service.actOnNativeResource(
        resource,
        NativeGatewayResourceAction.restart,
      ),
      throwsA(isA<CoordinatorMutationOutcomeUnknownException>()),
    );

    expect(core.operationReads, <String>[testOperationId]);
    expect(core.inventoryReads, 1);
  });

  test(
    'unknown lease outcome replays the exact request and key once',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final lease = leaseFixture(projectId: project.id, serverId: resource.id);
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id, projectId: project.id),
        ],
        inventory: inventoryFixture(project: project, resource: resource),
        leaseResults: <Object>[
          const CoordinatorMutationOutcomeUnknownException(
            method: 'POST',
            path: '/ports/leases',
            timeout: Duration(seconds: 15),
          ),
          lease,
        ],
      );
      final service = serviceFixture(core);
      await service.loadNativeInventory();

      final result = await service.leaseNativePort(
        project: project,
        server: resource,
        firstPort: 30000,
        lastPort: 30100,
        preferredPort: 30001,
        purpose: 'preview',
      );

      expect(result, same(lease));
      expect(core.leaseKeys, hasLength(2));
      expect(core.leaseKeys[0], core.leaseKeys[1]);
      expect(core.leaseRequests[0], same(core.leaseRequests[1]));
    },
  );

  test(
    'pending exact action replay follows its canonical operation to terminal',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id),
        ],
        inventory: inventoryFixture(project: project, resource: resource),
        actionResults: <Object>[
          unknownMutation(),
          operationInProgressProblem(),
        ],
        operationResults: <Object>[
          operationFixture(status: NativeGatewayOperationStatus.running),
          operationFixture(),
        ],
      );
      final service = serviceFixture(core);
      await service.loadNativeInventory();

      final result = await service.actOnNativeResource(
        resource,
        NativeGatewayResourceAction.restart,
      );

      expect(result.isSuccessful, isTrue);
      expect(core.resourceActionKeys, hasLength(2));
      expect(core.resourceActionKeys[0], core.resourceActionKeys[1]);
      expect(core.operationReads, <String>[testOperationId, testOperationId]);
    },
  );

  test(
    'pending replay binds the problem operation id to the fetched snapshot',
    () async {
      const otherOperationId = '223e4567-e89b-42d3-a456-426614174000';
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id),
        ],
        inventory: inventoryFixture(project: project, resource: resource),
        actionResults: <Object>[
          unknownMutation(),
          operationInProgressProblem(),
        ],
        operationResults: <Object>[
          operationFixture(operationId: otherOperationId),
        ],
      );
      final service = serviceFixture(core);
      await service.loadNativeInventory();

      await expectLater(
        service.actOnNativeResource(
          resource,
          NativeGatewayResourceAction.restart,
        ),
        throwsA(isA<CoordinatorMutationOutcomeUnknownException>()),
      );

      expect(core.operationReads, <String>[testOperationId]);
      expect(core.inventoryReads, 1);
    },
  );

  test('pending replay never follows another canonical operation id', () async {
    const otherOperationId = '223e4567-e89b-42d3-a456-426614174000';
    final project = projectFixture();
    final resource = resourceFixture(projectId: project.id);
    final problem = operationInProgressProblem(operationId: otherOperationId);
    final core = FakeNativeCore(
      sessions: <NativeGatewaySession>[sessionFixture(resourceId: resource.id)],
      inventory: inventoryFixture(project: project, resource: resource),
      actionResults: <Object>[unknownMutation(), problem],
    );
    final service = serviceFixture(core);
    await service.loadNativeInventory();

    await expectLater(
      service.actOnNativeResource(
        resource,
        NativeGatewayResourceAction.restart,
      ),
      throwsA(same(problem)),
    );

    expect(core.resourceActionKeys, hasLength(2));
    expect(core.resourceActionKeys[0], core.resourceActionKeys[1]);
    expect(core.operationReads, isEmpty);
  });

  test(
    'pending lease replay resolves the exact operation target from inventory',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final lease = leaseFixture(projectId: project.id, serverId: resource.id);
      final initial = inventoryFixture(project: project, resource: resource);
      final committed = inventoryFixture(
        project: project,
        resource: resource,
        leases: <NativeGatewayPortLease>[lease],
      );
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id, projectId: project.id),
        ],
        inventory: initial,
        inventories: <NativeGatewayInventory>[initial, committed],
        leaseResults: <Object>[
          unknownMutation(path: '/ports/leases'),
          operationInProgressProblem(),
        ],
        operationResults: <Object>[
          operationFixture(
            targetId: lease.id,
            targetKind: NativeGatewayOperationTargetKind.portLease,
          ),
        ],
      );
      final service = serviceFixture(core);
      await service.loadNativeInventory();

      final result = await service.leaseNativePort(
        project: project,
        server: resource,
        firstPort: 30000,
        lastPort: 30100,
        preferredPort: 30001,
        purpose: 'preview',
      );

      expect(result, same(lease));
      expect(core.leaseKeys, hasLength(2));
      expect(core.leaseKeys[0], core.leaseKeys[1]);
      expect(core.leaseRequests[0], same(core.leaseRequests[1]));
      expect(core.operationReads, <String>[testOperationId]);
      expect(service.currentNativeInventory!.leases.single, same(lease));
    },
  );

  test(
    'pending lease replay never substitutes a different inventory lease',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final lease = leaseFixture(projectId: project.id, serverId: resource.id);
      final initial = inventoryFixture(project: project, resource: resource);
      final committed = inventoryFixture(
        project: project,
        resource: resource,
        leases: <NativeGatewayPortLease>[lease],
      );
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id, projectId: project.id),
        ],
        inventory: initial,
        inventories: <NativeGatewayInventory>[initial, committed],
        leaseResults: <Object>[
          unknownMutation(path: '/ports/leases'),
          operationInProgressProblem(),
        ],
        operationResults: <Object>[
          operationFixture(
            targetId: 'other-lease',
            targetKind: NativeGatewayOperationTargetKind.portLease,
          ),
        ],
      );
      final service = serviceFixture(core);
      await service.loadNativeInventory();

      await expectLater(
        service.leaseNativePort(
          project: project,
          server: resource,
          firstPort: 30000,
          lastPort: 30100,
          preferredPort: 30001,
          purpose: 'preview',
        ),
        throwsA(isA<CoordinatorMutationOutcomeUnknownException>()),
      );
    },
  );

  test(
    'pending release replay completes only after the exact lease is inactive',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final lease = leaseFixture(projectId: project.id, serverId: resource.id);
      final released = leaseFixture(
        projectId: project.id,
        serverId: resource.id,
        status: NativeGatewayPortLeaseStatus.released,
        releasable: false,
      );
      final initial = inventoryFixture(
        project: project,
        resource: resource,
        leases: <NativeGatewayPortLease>[lease],
      );
      final committed = inventoryFixture(
        project: project,
        resource: resource,
        leases: <NativeGatewayPortLease>[released],
      );
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id, projectId: project.id),
        ],
        inventory: initial,
        inventories: <NativeGatewayInventory>[initial, committed],
        releaseResults: <Object>[
          unknownMutation(path: '/ports/leases/${lease.id}'),
          operationInProgressProblem(),
        ],
        operationResults: <Object>[
          operationFixture(
            targetId: lease.id,
            targetKind: NativeGatewayOperationTargetKind.portLease,
          ),
        ],
      );
      final service = serviceFixture(core);
      await service.loadNativeInventory();

      await service.releaseNativePort(lease);

      expect(core.releaseKeys, hasLength(2));
      expect(core.releaseKeys[0], core.releaseKeys[1]);
      expect(core.releasedLeaseIds, <String>[lease.id, lease.id]);
      expect(core.operationReads, <String>[testOperationId]);
      expect(
        service.currentNativeInventory!.leases.single.status,
        NativeGatewayPortLeaseStatus.released,
      );
    },
  );

  test(
    'pending release remains unknown while the exact lease is still active',
    () async {
      final project = projectFixture();
      final resource = resourceFixture(projectId: project.id);
      final lease = leaseFixture(projectId: project.id, serverId: resource.id);
      final inventory = inventoryFixture(
        project: project,
        resource: resource,
        leases: <NativeGatewayPortLease>[lease],
      );
      final core = FakeNativeCore(
        sessions: <NativeGatewaySession>[
          sessionFixture(resourceId: resource.id, projectId: project.id),
        ],
        inventory: inventory,
        releaseResults: <Object>[
          unknownMutation(path: '/ports/leases/${lease.id}'),
          operationInProgressProblem(),
        ],
        operationResults: <Object>[
          operationFixture(
            targetId: lease.id,
            targetKind: NativeGatewayOperationTargetKind.portLease,
          ),
        ],
      );
      final service = serviceFixture(core);
      await service.loadNativeInventory();

      await expectLater(
        service.releaseNativePort(lease),
        throwsA(isA<CoordinatorMutationOutcomeUnknownException>()),
      );

      expect(service.currentNativeInventory!.leases.single, same(lease));
    },
  );

  test('other or malformed 409 problems remain untouched', () async {
    final project = projectFixture();
    final resource = resourceFixture(projectId: project.id);
    final problem = operationInProgressProblem(
      operationId: testOperationId.toUpperCase(),
    );
    final core = FakeNativeCore(
      sessions: <NativeGatewaySession>[sessionFixture(resourceId: resource.id)],
      inventory: inventoryFixture(project: project, resource: resource),
      actionResults: <Object>[unknownMutation(), problem],
    );
    final service = serviceFixture(core);
    await service.loadNativeInventory();

    await expectLater(
      service.actOnNativeResource(
        resource,
        NativeGatewayResourceAction.restart,
      ),
      throwsA(same(problem)),
    );

    expect(core.operationReads, isEmpty);
  });
}

const testOperationId = '123e4567-e89b-42d3-a456-426614174000';

CoordinatorMutationOutcomeUnknownException unknownMutation({
  String path = '/resources/id/actions/restart',
}) => CoordinatorMutationOutcomeUnknownException(
  method: 'POST',
  path: path,
  timeout: const Duration(seconds: 15),
);

NativeGatewayProblemException operationInProgressProblem({
  String operationId = testOperationId,
}) => NativeGatewayProblemException(
  httpStatus: 409,
  problem: NativeGatewayProblem(
    type: 'https://console.classified.guru/problems/operation-in-progress',
    title: 'Operation in progress',
    status: 409,
    code: 'operation_in_progress',
    blockers: const <NativeGatewayBlocker>[],
    extensions: <String, Object?>{'operationId': operationId},
  ),
);

NativeGatewayCoordinatorService serviceFixture(FakeNativeCore core) {
  final configuration = oauthConfiguration();
  final store = MemorySessionStore()
    ..credential = NativeRefreshCredential(
      bindingKey: configuration.bindingKey,
      refreshToken: 'r' * 40,
      scopes: const <String>{'inventory:read', 'resources:act', 'ports:manage'},
      updatedAt: DateTime.utc(2026),
      deviceSessionId: 'device-1',
    );
  final manager = NativeOAuthSessionManager(
    configuration,
    NativeOAuthClient(
      MockClient((_) async => throw StateError('unexpected OAuth request')),
    ),
    store,
    NoopCallbackRouter(),
    NoopBrowser(),
  );
  return NativeGatewayCoordinatorService(
    core,
    manager,
    core.sessions.first,
    nativeMeta: metaFixture(),
    delay: (_) async {},
    idempotencyKeyGenerator: () =>
        NativeGatewayIdempotencyKey.parse(testOperationId),
  );
}

NativeGatewayMeta metaFixture() => NativeGatewayMeta(
  contractVersion: '2.0.0',
  serverVersion: '2.0.0',
  minimumClientVersion: '0.2.0',
  issuer: Uri.parse('https://console.classified.guru'),
  authorizationEndpoint: Uri.parse(
    'https://console.classified.guru/oauth/authorize',
  ),
  tokenEndpoint: Uri.parse('https://console.classified.guru/oauth/token'),
  revocationEndpoint: Uri.parse('https://console.classified.guru/oauth/revoke'),
  publicClientId: nativeOAuthClientId,
  pkceMethods: const <NativeGatewayPkceMethod>{NativeGatewayPkceMethod.s256},
  capabilities: NativeGatewayCapabilities(const <NativeGatewayCapability>{
    NativeGatewayCapability.inventoryRead,
    NativeGatewayCapability.eventsRead,
    NativeGatewayCapability.resourcesAct,
    NativeGatewayCapability.logsRead,
    NativeGatewayCapability.portsManage,
  }),
);

NativeGatewaySession sessionFixture({
  required String resourceId,
  String? projectId,
  Set<String> scopes = const <String>{
    'inventory:read',
    'resources:act',
    'ports:manage',
  },
  Set<String> permissions = const <String>{'resources:act', 'logs:read'},
}) {
  return NativeGatewaySession(
    userId: 'user-1',
    email: 'user@example.com',
    deviceSessionId: 'device-1',
    roles: const <NativeGatewaySessionRole>{
      NativeGatewaySessionRole.invitedOperator,
    },
    scopes: scopes,
    grants: <NativeGatewayGrant>[
      NativeGatewayGrant(resourceId: resourceId, permissions: permissions),
      if (projectId != null)
        NativeGatewayGrant(
          resourceId: projectId,
          permissions: const <String>{'ports:manage', 'resources:act'},
        ),
    ],
    expiresAt: DateTime.utc(2030),
  );
}

NativeGatewayProject projectFixture() => NativeGatewayProject(
  id: 'project-1',
  displayName: 'Project One',
  state: NativeGatewayResourceState.running,
  allowedActions: const <NativeGatewayResourceAction>[
    NativeGatewayResourceAction.restart,
  ],
);

NativeGatewayResource resourceFixture({required String projectId}) =>
    NativeGatewayResource(
      id: 'resource-1',
      projectId: projectId,
      kind: NativeGatewayResourceKind.server,
      displayName: 'Preview',
      state: NativeGatewayResourceState.running,
      allowedActions: const <NativeGatewayResourceAction>[
        NativeGatewayResourceAction.restart,
        NativeGatewayResourceAction.stop,
      ],
      blockers: const <NativeGatewayBlocker>[],
      port: 30001,
    );

NativeGatewayPortLease leaseFixture({
  required String projectId,
  required String serverId,
  NativeGatewayPortLeaseStatus status = NativeGatewayPortLeaseStatus.active,
  bool releasable = true,
}) => NativeGatewayPortLease(
  id: 'lease-1',
  projectId: projectId,
  serverResourceId: serverId,
  port: 30001,
  purpose: 'preview',
  status: status,
  releasable: releasable,
  expiresAt: DateTime.utc(2030),
);

NativeGatewayInventory inventoryFixture({
  required NativeGatewayProject project,
  required NativeGatewayResource resource,
  List<NativeGatewayPortLease> leases = const <NativeGatewayPortLease>[],
}) => NativeGatewayInventory(
  revision: 'revision-1',
  observedAt: DateTime.utc(2026),
  partial: false,
  projects: <NativeGatewayProject>[project],
  resources: <NativeGatewayResource>[resource],
  leases: leases,
  blockers: const <NativeGatewayBlocker>[],
);

NativeGatewayOperation operationFixture({
  String operationId = testOperationId,
  NativeGatewayOperationStatus status = NativeGatewayOperationStatus.succeeded,
  String targetId = 'resource-1',
  NativeGatewayOperationTargetKind targetKind =
      NativeGatewayOperationTargetKind.server,
  NativeGatewayOperationTargetStatus? targetStatus,
  bool partial = false,
  bool needsAttention = false,
}) => NativeGatewayOperation(
  id: operationId,
  status: status,
  partial: partial,
  needsAttention: needsAttention,
  startedAt: DateTime.utc(2026),
  finishedAt:
      status == NativeGatewayOperationStatus.queued ||
          status == NativeGatewayOperationStatus.running
      ? null
      : DateTime.utc(2026),
  results: <NativeGatewayOperationTargetResult>[
    NativeGatewayOperationTargetResult(
      targetId: targetId,
      targetKind: targetKind,
      status:
          targetStatus ??
          switch (status) {
            NativeGatewayOperationStatus.queued =>
              NativeGatewayOperationTargetStatus.queued,
            NativeGatewayOperationStatus.running =>
              NativeGatewayOperationTargetStatus.running,
            NativeGatewayOperationStatus.succeeded ||
            NativeGatewayOperationStatus.partial =>
              NativeGatewayOperationTargetStatus.succeeded,
            NativeGatewayOperationStatus.failed ||
            NativeGatewayOperationStatus.needsAttention =>
              NativeGatewayOperationTargetStatus.failed,
            NativeGatewayOperationStatus.timedOut =>
              NativeGatewayOperationTargetStatus.timedOut,
            NativeGatewayOperationStatus.cancelled =>
              NativeGatewayOperationTargetStatus.cancelled,
          },
      message: 'Completed',
      evidenceIds: const <String>[],
    ),
  ],
  errors: const <NativeGatewayProblem>[],
);

NativeOAuthConfiguration oauthConfiguration() => NativeOAuthConfiguration(
  gatewayEndpoint: Uri.parse('https://console.classified.guru/api/v2'),
  issuer: Uri.parse('https://console.classified.guru'),
  authorizationEndpoint: Uri.parse(
    'https://console.classified.guru/oauth/authorize',
  ),
  tokenEndpoint: Uri.parse('https://console.classified.guru/oauth/token'),
  revocationEndpoint: Uri.parse('https://console.classified.guru/oauth/revoke'),
  clientId: nativeOAuthClientId,
  pkceMethods: const <String>{'S256'},
);

final class FakeNativeCore implements NativeGatewayV2CoreApi {
  FakeNativeCore({
    required this.sessions,
    required NativeGatewayInventory inventory,
    List<NativeGatewayInventory>? inventories,
    this.actionResults = const <Object>[],
    this.leaseResults = const <Object>[],
    this.releaseResults = const <Object>[],
    this.operationResults = const <Object>[],
  }) : inventories = inventories ?? <NativeGatewayInventory>[inventory];

  final List<NativeGatewaySession> sessions;
  final List<NativeGatewayInventory> inventories;
  final List<Object> actionResults;
  final List<Object> leaseResults;
  final List<Object> releaseResults;
  final List<Object> operationResults;
  final List<NativeGatewayIdempotencyKey> resourceActionKeys =
      <NativeGatewayIdempotencyKey>[];
  final List<NativeGatewayIdempotencyKey> leaseKeys =
      <NativeGatewayIdempotencyKey>[];
  final List<NativeGatewayLeaseRequest> leaseRequests =
      <NativeGatewayLeaseRequest>[];
  final List<NativeGatewayIdempotencyKey> releaseKeys =
      <NativeGatewayIdempotencyKey>[];
  final List<String> releasedLeaseIds = <String>[];
  final List<String> operationReads = <String>[];
  int _sessionIndex = 0;
  int _actionIndex = 0;
  int _leaseIndex = 0;
  int _releaseIndex = 0;
  int _operationIndex = 0;
  int inventoryReads = 0;

  @override
  CoordinatorEndpoint get endpoint => CoordinatorEndpoint.nativeV2(
    Uri.parse('https://console.classified.guru/api/v2'),
  );

  @override
  Future<NativeGatewaySession> readSession() async {
    final index = _sessionIndex < sessions.length
        ? _sessionIndex
        : sessions.length - 1;
    _sessionIndex += 1;
    return sessions[index];
  }

  @override
  Future<NativeGatewayConditionalResult<NativeGatewayInventory>> readInventory({
    NativeGatewayEntityTag? ifNoneMatch,
  }) async {
    final index = inventoryReads < inventories.length
        ? inventoryReads
        : inventories.length - 1;
    inventoryReads += 1;
    return NativeGatewayModified<NativeGatewayInventory>(
      value: inventories[index],
      entityTag: NativeGatewayEntityTag.parse('"revision-$inventoryReads"'),
    );
  }

  @override
  Future<NativeGatewayOperation> actOnResource({
    required String resourceId,
    required NativeGatewayResourceAction action,
    required NativeGatewayActionRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) async {
    resourceActionKeys.add(idempotencyKey);
    final result = actionResults[_actionIndex++];
    if (result is Exception) throw result;
    return result as NativeGatewayOperation;
  }

  @override
  Future<NativeGatewayPortLease> createPortLease({
    required NativeGatewayLeaseRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) async {
    leaseRequests.add(request);
    leaseKeys.add(idempotencyKey);
    final result = leaseResults[_leaseIndex++];
    if (result is Exception) throw result;
    return result as NativeGatewayPortLease;
  }

  @override
  Future<NativeGatewayOperation> actOnProject({
    required String projectId,
    required NativeGatewayResourceAction action,
    required NativeGatewayActionRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<NativeGatewayLifecyclePlan> createLifecyclePlan({
    required NativeGatewayLifecyclePlanRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<NativeGatewayOperation> applyLifecyclePlan({
    required String planId,
    required NativeGatewayLifecycleApplyRequest request,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<NativeGatewayEventPage> readEvents({String? after, int limit = 100}) =>
      throw UnimplementedError();

  @override
  Future<NativeGatewayLogPage> readResourceLogs({
    required String resourceId,
    String? cursor,
    int limit = 200,
  }) => throw UnimplementedError();

  @override
  Future<NativeGatewayDocument<NativeGatewayMeta>> readMeta() async =>
      NativeGatewayDocument<NativeGatewayMeta>(value: metaFixture());

  @override
  Future<NativeGatewayOperation> readOperation(String operationId) =>
      _nextOperation(operationId);

  Future<NativeGatewayOperation> _nextOperation(String operationId) async {
    operationReads.add(operationId);
    final result = operationResults[_operationIndex++];
    if (result is Exception) throw result;
    return result as NativeGatewayOperation;
  }

  @override
  Future<void> releasePortLease({
    required String leaseId,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) async {
    releasedLeaseIds.add(leaseId);
    releaseKeys.add(idempotencyKey);
    final result = releaseResults[_releaseIndex++];
    if (result is Exception) throw result;
  }

  @override
  Future<void> revokeCurrentSession() async {}

  @override
  void close() {}
}

final class MemorySessionStore implements NativeSessionStore {
  NativeRefreshCredential? credential;

  @override
  Future<void> clearCredential() async => credential = null;

  @override
  Future<void> clearPendingAuthorization() async {}

  @override
  Future<NativeRefreshCredential?> readCredential() async => credential;

  @override
  Future<NativePendingAuthorization?> readPendingAuthorization() async => null;

  @override
  Future<void> writeCredential(NativeRefreshCredential value) async =>
      credential = value;

  @override
  Future<void> writePendingAuthorization(
    NativePendingAuthorization authorization,
  ) async {}
}

final class NoopCallbackRouter implements NativeAuthorizationCallbackRouter {
  @override
  void close() {}

  @override
  Future<void> initialize() async {}

  @override
  Uri? takeBufferedCallback(String state) => null;

  @override
  Future<Uri> waitForCallback(
    String state, {
    Duration timeout = const Duration(minutes: 5),
  }) => throw UnimplementedError();
}

final class NoopBrowser implements NativeSystemBrowserLauncher {
  @override
  Future<void> open(Uri uri) => throw UnimplementedError();
}
