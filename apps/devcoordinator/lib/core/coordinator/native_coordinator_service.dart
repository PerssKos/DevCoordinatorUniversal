import 'dart:async';

import 'package:coordinator_client/coordinator_client.dart';

import '../../app/app_services.dart';
import '../auth/native_oauth_session_manager.dart';

/// A durably retained operation reached a terminal state without conclusive
/// success.
///
/// The operation is retained so the UI can show the exact terminal result
/// while keeping all further mutations fenced until an explicit refresh.
final class NativeOperationFailedException implements Exception {
  const NativeOperationFailedException(this.operation);

  final NativeGatewayOperation operation;

  String get message =>
      'The operation finished with status ${operation.status.name} and did '
      'not conclusively succeed.';

  @override
  String toString() => 'NativeOperationFailedException: $message';
}

final class NativeGatewayCoordinatorService
    implements NativeAppCoordinatorService {
  NativeGatewayCoordinatorService(
    this._gateway,
    this._sessionManager,
    this._nativeSession, {
    required this.nativeMeta,
    Future<void> Function(Duration duration)? delay,
    NativeGatewayIdempotencyKey Function()? idempotencyKeyGenerator,
    this.operationTimeout = const Duration(minutes: 2),
  }) : _delay = delay ?? Future<void>.delayed,
       _idempotencyKeyGenerator =
           idempotencyKeyGenerator ?? NativeGatewayIdempotencyKey.generate;

  final NativeGatewayV2CoreApi _gateway;
  final NativeOAuthSessionManager _sessionManager;
  final Future<void> Function(Duration duration) _delay;
  final NativeGatewayIdempotencyKey Function() _idempotencyKeyGenerator;
  final Duration operationTimeout;

  @override
  final NativeGatewayMeta nativeMeta;

  NativeGatewaySession _nativeSession;

  @override
  NativeGatewaySession get nativeSession => _nativeSession;

  NativeGatewayInventory? _inventory;
  NativeGatewayEntityTag? _entityTag;

  @override
  NativeGatewayInventory? get currentNativeInventory => _inventory;

  @override
  NativeGatewayEntityTag? get currentNativeEntityTag => _entityTag;

  @override
  bool supports(CoordinatorCapability capability) => switch (capability) {
    CoordinatorCapability.inventoryRead => _supportsNative(
      NativeGatewayCapability.inventoryRead,
      'inventory:read',
    ),
    CoordinatorCapability.eventsRead => _supportsNative(
      NativeGatewayCapability.eventsRead,
      'inventory:read',
    ),
    CoordinatorCapability.logsRead => _supportsNative(
      NativeGatewayCapability.logsRead,
      'inventory:read',
    ),
    CoordinatorCapability.serverLifecycle ||
    CoordinatorCapability.projectLifecycle ||
    CoordinatorCapability.containerLifecycle => _supportsNative(
      NativeGatewayCapability.resourcesAct,
      'resources:act',
    ),
    CoordinatorCapability.portLeases => _supportsNative(
      NativeGatewayCapability.portsManage,
      'ports:manage',
    ),
    CoordinatorCapability.durableLifecycle => _supportsNative(
      NativeGatewayCapability.lifecycleManage,
      'lifecycle:manage',
    ),
  };

  bool _supportsNative(NativeGatewayCapability capability, String scope) =>
      nativeMeta.capabilities.supports(capability) &&
      nativeSession.hasScope(scope);

  @override
  Future<NativeGatewayInventory> loadNativeInventory() async {
    final refreshedSession = await _gateway.readSession();
    if (!refreshedSession.expiresAt.isAfter(DateTime.now().toUtc())) {
      await _sessionManager.clearAfterRemoteRevocation();
      throw const CoordinatorAuthenticationException(
        'The native gateway session has expired.',
      );
    }
    final result = await _gateway.readInventory(ifNoneMatch: _entityTag);
    switch (result) {
      case NativeGatewayModified<NativeGatewayInventory>(
        :final value,
        :final entityTag,
      ):
        _inventory = value;
        _entityTag = entityTag;
      case NativeGatewayNotModified<NativeGatewayInventory>():
        if (_inventory == null) {
          throw StateError(
            'The gateway returned not-modified before an inventory existed.',
          );
        }
    }
    // Commit session policy and its corresponding authoritative inventory
    // together, so controls cannot remain enabled from an older grant set.
    _nativeSession = refreshedSession;
    await _sessionManager.bindDeviceSession(refreshedSession.deviceSessionId);
    return _inventory!;
  }

  @override
  Future<CoordinatorInventory> loadInventory() {
    throw UnsupportedError(
      'Native inventory must not be converted into legacy path-shaped models.',
    );
  }

  @override
  NativeActionGate canActOnNativeProject(
    NativeGatewayProject project,
    NativeGatewayResourceAction action,
  ) {
    final current = _inventory?.projects
        .where((candidate) => candidate.id == project.id)
        .firstOrNull;
    return _mutationGate(
      targetIsCurrent: identical(current, project),
      targetId: project.id,
      action: action,
      allowedActions: project.allowedActions,
      blockers: const <NativeGatewayBlocker>[],
    );
  }

  @override
  NativeActionGate canActOnNativeResource(
    NativeGatewayResource resource,
    NativeGatewayResourceAction action,
  ) {
    final current = _inventory?.resources
        .where((candidate) => candidate.id == resource.id)
        .firstOrNull;
    return _mutationGate(
      targetIsCurrent: identical(current, resource),
      targetId: resource.id,
      action: action,
      allowedActions: resource.allowedActions,
      blockers: resource.blockers,
    );
  }

  NativeActionGate _mutationGate({
    required bool targetIsCurrent,
    required String targetId,
    required NativeGatewayResourceAction action,
    required List<NativeGatewayResourceAction> allowedActions,
    required List<NativeGatewayBlocker> blockers,
  }) {
    if (!_supportsNative(
      NativeGatewayCapability.resourcesAct,
      'resources:act',
    )) {
      return const NativeActionGate.blocked(
        'The gateway capability or session scope does not allow actions.',
      );
    }
    if (_inventory == null || _entityTag == null || _inventory!.partial) {
      return const NativeActionGate.blocked(
        'A complete inventory with a current strong ETag is required.',
      );
    }
    if (!targetIsCurrent) {
      return const NativeActionGate.blocked(
        'Select the exact target from the current inventory.',
      );
    }
    if (!nativeSession.hasPermission(targetId, 'resources:act')) {
      return const NativeActionGate.blocked(
        'The current session grant does not authorize this target.',
      );
    }
    if (!allowedActions.contains(action)) {
      return const NativeActionGate.blocked(
        'The gateway does not allow this action in the current target state.',
      );
    }
    if (blockers.isNotEmpty) {
      return NativeActionGate.blocked(blockers.first.message);
    }
    return const NativeActionGate.allowed();
  }

  @override
  NativeActionGate canReadNativeLogs(NativeGatewayResource resource) {
    final current = _inventory?.resources
        .where((candidate) => candidate.id == resource.id)
        .firstOrNull;
    if (!_supportsNative(NativeGatewayCapability.logsRead, 'inventory:read')) {
      return const NativeActionGate.blocked(
        'The gateway capability or session scope does not allow logs.',
      );
    }
    if (!identical(current, resource)) {
      return const NativeActionGate.blocked(
        'Select the exact resource from the current inventory.',
      );
    }
    if (!nativeSession.hasPermission(resource.id, 'logs:read')) {
      return const NativeActionGate.blocked(
        'The current session grant does not authorize these logs.',
      );
    }
    return const NativeActionGate.allowed();
  }

  @override
  NativeActionGate canManageNativeLease({
    required String projectId,
    String? leaseId,
  }) {
    if (!_supportsNative(NativeGatewayCapability.portsManage, 'ports:manage')) {
      return const NativeActionGate.blocked(
        'The gateway capability or session scope does not allow port leases.',
      );
    }
    final inventory = _inventory;
    if (inventory == null || _entityTag == null || inventory.partial) {
      return const NativeActionGate.blocked(
        'A complete inventory with a current strong ETag is required.',
      );
    }
    if (!inventory.projects.any((project) => project.id == projectId)) {
      return const NativeActionGate.blocked(
        'The lease project is not in the current inventory.',
      );
    }
    if (leaseId != null &&
        !inventory.leases.any(
          (lease) =>
              lease.id == leaseId &&
              lease.projectId == projectId &&
              lease.releasable,
        )) {
      return const NativeActionGate.blocked(
        'The exact releasable lease is not in the current inventory.',
      );
    }
    if (!nativeSession.hasPermission(projectId, 'ports:manage')) {
      return const NativeActionGate.blocked(
        'The current session grant does not authorize this project.',
      );
    }
    return const NativeActionGate.allowed();
  }

  @override
  Future<NativeGatewayOperation> actOnNativeProject(
    NativeGatewayProject project,
    NativeGatewayResourceAction action, {
    String? reason,
  }) async {
    final gate = canActOnNativeProject(project, action);
    _requireAllowed(gate);
    final request = NativeGatewayActionRequest(reason: reason);
    final entityTag = _entityTag!;
    final idempotencyKey = _idempotencyKeyGenerator();
    final operation = await _withExactReplay(
      () => _gateway.actOnProject(
        projectId: project.id,
        action: action,
        request: request,
        ifMatch: entityTag,
        idempotencyKey: idempotencyKey,
      ),
      expectedOperationId: idempotencyKey.value,
      reconcileOperationInProgress: _readExactOperation,
    );
    return _poll(
      operation,
      expectedOperationId: idempotencyKey.value,
      expectedTargetId: project.id,
      expectedTargetKind: NativeGatewayOperationTargetKind.project,
      mutationPath: '/projects/{projectId}/actions/${action.name}',
    );
  }

  @override
  Future<NativeGatewayOperation> actOnNativeResource(
    NativeGatewayResource resource,
    NativeGatewayResourceAction action, {
    String? reason,
  }) async {
    final gate = canActOnNativeResource(resource, action);
    _requireAllowed(gate);
    final request = NativeGatewayActionRequest(reason: reason);
    final entityTag = _entityTag!;
    final idempotencyKey = _idempotencyKeyGenerator();
    final operation = await _withExactReplay(
      () => _gateway.actOnResource(
        resourceId: resource.id,
        action: action,
        request: request,
        ifMatch: entityTag,
        idempotencyKey: idempotencyKey,
      ),
      expectedOperationId: idempotencyKey.value,
      reconcileOperationInProgress: _readExactOperation,
    );
    return _poll(
      operation,
      expectedOperationId: idempotencyKey.value,
      expectedTargetId: resource.id,
      expectedTargetKind: _operationTargetKind(resource.kind),
      mutationPath: '/resources/{resourceId}/actions/${action.name}',
    );
  }

  Future<NativeGatewayOperation> _poll(
    NativeGatewayOperation operation, {
    required String expectedOperationId,
    required String mutationPath,
    String? expectedTargetId,
    NativeGatewayOperationTargetKind? expectedTargetKind,
  }) async {
    final deadline = DateTime.now().toUtc().add(operationTimeout);
    var current = operation;
    _requireOperationBinding(
      current,
      expectedOperationId: expectedOperationId,
      expectedTargetId: expectedTargetId,
      expectedTargetKind: expectedTargetKind,
      mutationPath: mutationPath,
    );
    while (!current.isTerminal) {
      if (!DateTime.now().toUtc().isBefore(deadline)) {
        throw CoordinatorTimeoutException(
          'The operation is still running. Refresh to reconcile its result.',
          timeout: operationTimeout,
        );
      }
      await _delay(const Duration(milliseconds: 750));
      current = await _readExactOperation(expectedOperationId);
      _requireOperationBinding(
        current,
        expectedOperationId: expectedOperationId,
        expectedTargetId: expectedTargetId,
        expectedTargetKind: expectedTargetKind,
        mutationPath: mutationPath,
      );
    }
    if (!current.isSuccessful) {
      try {
        await loadNativeInventory();
      } catch (_) {
        // The retained terminal failure remains the primary result. The
        // controller keeps the last committed snapshot fenced until refresh.
      }
      throw NativeOperationFailedException(current);
    }
    await loadNativeInventory();
    return current;
  }

  @override
  Future<NativeGatewayLogPage> readNativeLogs(
    NativeGatewayResource resource, {
    String? cursor,
    int limit = 200,
  }) async {
    _requireAllowed(canReadNativeLogs(resource));
    return _withAuthorizationRefresh(
      () => _gateway.readResourceLogs(
        resourceId: resource.id,
        cursor: cursor,
        limit: limit,
      ),
    );
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
  }) async {
    _requireAllowed(canManageNativeLease(projectId: project.id));
    final currentProject = _inventory!.projects
        .where((candidate) => candidate.id == project.id)
        .firstOrNull;
    final currentServer = _inventory!.resources
        .where((candidate) => candidate.id == server.id)
        .firstOrNull;
    if (!identical(currentProject, project) ||
        !identical(currentServer, server) ||
        server.kind != NativeGatewayResourceKind.server ||
        server.projectId != project.id) {
      throw StateError(
        'Port leasing requires the exact current project and server resource.',
      );
    }
    final request = NativeGatewayLeaseRequest(
      projectId: project.id,
      serverResourceId: server.id,
      firstPort: firstPort,
      lastPort: lastPort,
      purpose: purpose,
      preferredPort: preferredPort,
      ttlSeconds: ttl?.inSeconds,
    );
    final entityTag = _entityTag!;
    final idempotencyKey = _idempotencyKeyGenerator();
    final lease = await _withExactReplay(
      () => _gateway.createPortLease(
        request: request,
        ifMatch: entityTag,
        idempotencyKey: idempotencyKey,
      ),
      reconcileOperationInProgress: (operationId) =>
          _reconcileCreatedLease(operationId, request),
      expectedOperationId: idempotencyKey.value,
    );
    await loadNativeInventory();
    return lease;
  }

  @override
  Future<void> releaseNativePort(NativeGatewayPortLease lease) async {
    _requireAllowed(
      canManageNativeLease(projectId: lease.projectId, leaseId: lease.id),
    );
    final current = _inventory!.leases
        .where((candidate) => candidate.id == lease.id)
        .firstOrNull;
    if (!identical(current, lease)) {
      throw StateError('Select the exact lease from the current inventory.');
    }
    final entityTag = _entityTag!;
    final idempotencyKey = _idempotencyKeyGenerator();
    var reconciledOperationInProgress = false;
    await _withExactReplay(
      () => _gateway.releasePortLease(
        leaseId: lease.id,
        ifMatch: entityTag,
        idempotencyKey: idempotencyKey,
      ),
      reconcileOperationInProgress: (operationId) async {
        reconciledOperationInProgress = true;
        await _poll(
          await _readExactOperation(operationId),
          expectedOperationId: operationId,
          expectedTargetId: lease.id,
          expectedTargetKind: NativeGatewayOperationTargetKind.portLease,
          mutationPath: '/ports/leases/{leaseId}',
        );
      },
      expectedOperationId: idempotencyKey.value,
    );
    await loadNativeInventory();
    if (reconciledOperationInProgress &&
        _inventory!.leases.any(
          (candidate) =>
              candidate.id == lease.id &&
              candidate.status == NativeGatewayPortLeaseStatus.active,
        )) {
      throw CoordinatorMutationOutcomeUnknownException(
        method: 'DELETE',
        path: '/ports/leases/${Uri.encodeComponent(lease.id)}',
        timeout: operationTimeout,
      );
    }
  }

  @override
  Future<NativeGatewayEventPage> loadNativeEvents({
    String? after,
    int limit = 100,
  }) async {
    if (!_supportsNative(
      NativeGatewayCapability.eventsRead,
      'inventory:read',
    )) {
      throw const CoordinatorCapabilityException(
        'Event history is not available to this session.',
      );
    }
    return _withAuthorizationRefresh(
      () => _gateway.readEvents(after: after, limit: limit),
    );
  }

  @override
  Future<void> revokeNativeSession() async {
    Object? sessionError;
    try {
      await _gateway.revokeCurrentSession();
    } catch (error) {
      sessionError = error;
    }
    try {
      await _sessionManager.revokeRefreshCredential();
    } catch (error) {
      throw StateError(
        'Remote session revocation is pending: ${_safeError(error)}',
      );
    }
    if (sessionError != null) {
      // Token-family revocation succeeded, so this device is conclusively
      // signed out even if DELETE /session returned an uncertain transport
      // result.
      return;
    }
  }

  Future<T> _withExactReplay<T>(
    Future<T> Function() request, {
    required String expectedOperationId,
    Future<T> Function(String operationId)? reconcileOperationInProgress,
  }) async {
    try {
      return await request();
    } on NativeGatewayProblemException catch (error) {
      await _refreshSessionAfterAuthorizationFailure(error);
      rethrow;
    } on CoordinatorMutationOutcomeUnknownException {
      try {
        // The closure captures one immutable request, ETag and idempotency key.
        // Never create a second user intent while reconciling this one.
        return await request();
      } on NativeGatewayProblemException catch (error) {
        final operationId = _operationInProgressId(error, expectedOperationId);
        if (operationId != null && reconcileOperationInProgress != null) {
          return reconcileOperationInProgress(operationId);
        }
        await _refreshSessionAfterAuthorizationFailure(error);
        rethrow;
      } on CoordinatorMutationOutcomeUnknownException {
        try {
          await loadNativeInventory();
        } catch (_) {
          // The original outcome remains unknown. Preserve the committed
          // snapshot and let the controller fence further mutations.
        }
        rethrow;
      }
    }
  }

  Future<NativeGatewayPortLease> _reconcileCreatedLease(
    String operationId,
    NativeGatewayLeaseRequest request,
  ) async {
    final operation = await _poll(
      await _readExactOperation(operationId),
      expectedOperationId: operationId,
      mutationPath: '/ports/leases',
    );
    final results = operation.results
        .where(
          (result) =>
              result.targetKind == NativeGatewayOperationTargetKind.portLease &&
              result.status == NativeGatewayOperationTargetStatus.succeeded,
        )
        .toList(growable: false);
    if (results.length != 1) {
      throw const CoordinatorProtocolException(
        'The completed port lease operation did not identify exactly one '
        'successful lease target.',
      );
    }
    final lease = _inventory!.leases
        .where((candidate) => candidate.id == results.single.targetId)
        .firstOrNull;
    if (lease == null ||
        lease.status != NativeGatewayPortLeaseStatus.active ||
        lease.projectId != request.projectId ||
        lease.serverResourceId != request.serverResourceId ||
        lease.purpose != request.purpose ||
        lease.port < request.firstPort ||
        lease.port > request.lastPort) {
      throw CoordinatorMutationOutcomeUnknownException(
        method: 'POST',
        path: '/ports/leases',
        timeout: operationTimeout,
      );
    }
    return lease;
  }

  static String? _operationInProgressId(
    NativeGatewayProblemException error,
    String expectedOperationId,
  ) {
    if (error.httpStatus != 409 ||
        error.problem.status != 409 ||
        error.problem.code != 'operation_in_progress') {
      return null;
    }
    final raw = error.problem.extensions['operationId'];
    if (raw is! String) {
      return null;
    }
    try {
      final normalized = NativeGatewayIdempotencyKey.parse(raw).value;
      return normalized == raw && normalized == expectedOperationId
          ? normalized
          : null;
    } on ArgumentError {
      return null;
    }
  }

  Future<NativeGatewayOperation> _readExactOperation(String operationId) async {
    final operation = await _gateway.readOperation(operationId);
    if (operation.id != operationId) {
      throw CoordinatorMutationOutcomeUnknownException(
        method: 'GET',
        path: '/operations/{operationId}',
        timeout: operationTimeout,
      );
    }
    return operation;
  }

  void _requireOperationBinding(
    NativeGatewayOperation operation, {
    required String expectedOperationId,
    required String? expectedTargetId,
    required NativeGatewayOperationTargetKind? expectedTargetKind,
    required String mutationPath,
  }) {
    if (operation.id != expectedOperationId) {
      throw CoordinatorMutationOutcomeUnknownException(
        method: 'POST',
        path: mutationPath,
        timeout: operationTimeout,
      );
    }
    if (expectedTargetId == null || expectedTargetKind == null) {
      return;
    }
    final results = operation.results;
    if (results.isEmpty && !operation.isSuccessful) {
      return;
    }
    if (results.length != 1 ||
        results.single.targetId != expectedTargetId ||
        results.single.targetKind != expectedTargetKind) {
      throw CoordinatorMutationOutcomeUnknownException(
        method: 'POST',
        path: mutationPath,
        timeout: operationTimeout,
      );
    }
  }

  static NativeGatewayOperationTargetKind _operationTargetKind(
    NativeGatewayResourceKind kind,
  ) => switch (kind) {
    NativeGatewayResourceKind.server => NativeGatewayOperationTargetKind.server,
    NativeGatewayResourceKind.container =>
      NativeGatewayOperationTargetKind.container,
    NativeGatewayResourceKind.database =>
      NativeGatewayOperationTargetKind.database,
    NativeGatewayResourceKind.worktree =>
      NativeGatewayOperationTargetKind.worktree,
  };

  Future<void> _refreshSessionAfterAuthorizationFailure(
    NativeGatewayProblemException error,
  ) async {
    if (error.httpStatus != 401 && error.httpStatus != 403) {
      return;
    }
    try {
      final refreshed = await _gateway.readSession();
      await _sessionManager.bindDeviceSession(refreshed.deviceSessionId);
      _nativeSession = refreshed;
    } catch (_) {
      if (error.httpStatus == 401) {
        await _sessionManager.clearAfterRemoteRevocation();
      }
    }
  }

  Future<T> _withAuthorizationRefresh<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NativeGatewayProblemException catch (error) {
      await _refreshSessionAfterAuthorizationFailure(error);
      rethrow;
    }
  }

  static void _requireAllowed(NativeActionGate gate) {
    if (!gate.allowed) {
      throw CoordinatorCapabilityException(
        gate.reason ?? 'The operation is not allowed.',
      );
    }
  }

  static String _safeError(Object error) => switch (error) {
    CoordinatorException(:final message) => message,
    _ => 'secure revocation could not be confirmed',
  };

  @override
  Future<CoordinatorActionResult> actOnServer(
    CoordinatorServer server,
    CoordinatorResourceAction action,
  ) {
    throw UnsupportedError('Use immutable native resource actions.');
  }

  @override
  Future<CoordinatorActionResult> actOnProject(
    CoordinatorProject project,
    CoordinatorProjectAction action,
  ) {
    throw UnsupportedError('Use immutable native project actions.');
  }

  @override
  Future<CoordinatorActionResult> actOnContainer(
    CoordinatorContainer container,
    CoordinatorResourceAction action,
  ) {
    throw UnsupportedError('Use immutable native resource actions.');
  }

  @override
  Future<CoordinatorLogResult> readServerLogs(
    CoordinatorServer server, {
    int tail = 200,
  }) {
    throw UnsupportedError('Use immutable native resource logs.');
  }

  @override
  Future<CoordinatorLogResult> readContainerLogs(
    CoordinatorContainer container, {
    int tail = 200,
  }) {
    throw UnsupportedError('Use immutable native resource logs.');
  }

  @override
  Future<CoordinatorLease> leasePort({
    required CoordinatorProject project,
    required CoordinatorServer server,
    required int firstPort,
    required int lastPort,
    int? preferredPort,
    Duration? ttl,
    String? purpose,
  }) {
    throw UnsupportedError('Use immutable native port-lease targets.');
  }

  @override
  Future<CoordinatorActionResult> releasePort(CoordinatorLease lease) {
    throw UnsupportedError('Use immutable native port-lease targets.');
  }

  @override
  void close() => _gateway.close();
}
