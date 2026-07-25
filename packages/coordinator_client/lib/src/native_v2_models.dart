import 'dart:collection';
import 'dart:math';

/// A strong HTTP entity tag used as a native-gateway state precondition.
///
/// Wildcards and weak validators are deliberately excluded: mutations must be
/// bound to the exact state the caller reviewed.
final class NativeGatewayEntityTag {
  NativeGatewayEntityTag._(this.value);

  factory NativeGatewayEntityTag.parse(String value) {
    if (value.length > 1024 ||
        value.startsWith('W/') ||
        !RegExp(r'^"[\x21\x23-\x7e]*"$').hasMatch(value)) {
      throw ArgumentError('must be a strong quoted HTTP entity tag', 'value');
    }
    return NativeGatewayEntityTag._(value);
  }

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is NativeGatewayEntityTag && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A canonical UUID suitable for the native gateway's Idempotency-Key header.
final class NativeGatewayIdempotencyKey {
  NativeGatewayIdempotencyKey._(this.value);

  factory NativeGatewayIdempotencyKey.parse(String value) {
    final normalized = value.toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(normalized)) {
      throw ArgumentError('must be a canonical UUID', 'value');
    }
    return NativeGatewayIdempotencyKey._(normalized);
  }

  factory NativeGatewayIdempotencyKey.generate([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return NativeGatewayIdempotencyKey._(
      '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}',
    );
  }

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is NativeGatewayIdempotencyKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

enum NativeGatewayCapability {
  inventoryRead('inventory.read'),
  eventsRead('events.read'),
  resourcesAct('resources.act'),
  logsRead('logs.read'),
  portsManage('ports.manage'),
  lifecycleManage('lifecycle.manage'),
  databasesRead('databases.read'),
  databasesBackup('databases.backup'),
  databasesRestore('databases.restore'),
  routesManage('routes.manage'),
  routesCredentialsManage('routes.credentials.manage'),
  accessManage('access.manage'),
  invitesManage('invites.manage'),
  telegramManage('telegram.manage'),
  unassignedRead('unassigned.read'),
  unassignedAttach('unassigned.attach'),
  unassignedRetire('unassigned.retire'),
  bulkStop('bulk.stop'),
  performanceRead('performance.read');

  const NativeGatewayCapability(this.wireValue);

  final String wireValue;

  static NativeGatewayCapability? fromWire(String value) {
    for (final capability in values) {
      if (capability.wireValue == value) {
        return capability;
      }
    }
    return null;
  }
}

final class NativeGatewayCapabilities {
  NativeGatewayCapabilities(Iterable<NativeGatewayCapability> values)
    : values = Set.unmodifiable(values);

  final Set<NativeGatewayCapability> values;

  bool supports(NativeGatewayCapability capability) =>
      values.contains(capability);
}

final class NativeGatewayMeta {
  NativeGatewayMeta({
    required this.contractVersion,
    required this.serverVersion,
    required this.minimumClientVersion,
    required this.capabilities,
  });

  final String contractVersion;
  final String serverVersion;
  final String minimumClientVersion;
  final NativeGatewayCapabilities capabilities;
}

enum NativeGatewaySessionRole {
  configuredOwner('configured_owner'),
  invitedOperator('invited_operator');

  const NativeGatewaySessionRole(this.wireValue);

  final String wireValue;
}

final class NativeGatewayGrant {
  NativeGatewayGrant({
    required this.resourceId,
    required Iterable<String> permissions,
  }) : permissions = Set.unmodifiable(permissions);

  final String resourceId;
  final Set<String> permissions;
}

final class NativeGatewaySession {
  NativeGatewaySession({
    required this.userId,
    required this.email,
    required this.deviceSessionId,
    required Iterable<NativeGatewaySessionRole> roles,
    required Iterable<String> scopes,
    required List<NativeGatewayGrant> grants,
    required this.expiresAt,
    this.displayName,
  }) : roles = Set.unmodifiable(roles),
       scopes = Set.unmodifiable(scopes),
       grants = List.unmodifiable(grants);

  final String userId;
  final String email;
  final String? displayName;
  final String deviceSessionId;
  final Set<NativeGatewaySessionRole> roles;
  final Set<String> scopes;
  final List<NativeGatewayGrant> grants;
  final DateTime expiresAt;

  bool hasScope(String scope) => scopes.contains(scope);

  bool hasPermission(String resourceId, String permission) => grants.any(
    (grant) =>
        grant.resourceId == resourceId &&
        grant.permissions.contains(permission),
  );
}

enum NativeGatewayResourceKind { server, container, database, worktree }

enum NativeGatewayResourceState {
  running,
  stopped,
  starting,
  stopping,
  unhealthy,
  archived,
  unknown,
}

enum NativeGatewayResourceAction { start, stop, restart }

final class NativeGatewayBlocker {
  const NativeGatewayBlocker({
    required this.code,
    required this.message,
    this.recovery,
  });

  final String code;
  final String message;
  final String? recovery;
}

final class NativeGatewayProject {
  NativeGatewayProject({
    required this.id,
    required this.displayName,
    required this.state,
    required List<NativeGatewayResourceAction> allowedActions,
  }) : allowedActions = List.unmodifiable(allowedActions);

  final String id;
  final String displayName;
  final NativeGatewayResourceState state;
  final List<NativeGatewayResourceAction> allowedActions;
}

final class NativeGatewayResource {
  NativeGatewayResource({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.state,
    required List<NativeGatewayResourceAction> allowedActions,
    required List<NativeGatewayBlocker> blockers,
    this.projectId,
    this.port,
    this.cpuPercent,
    this.memoryBytes,
  }) : allowedActions = List.unmodifiable(allowedActions),
       blockers = List.unmodifiable(blockers);

  final String id;
  final String? projectId;
  final NativeGatewayResourceKind kind;
  final String displayName;
  final NativeGatewayResourceState state;
  final int? port;
  final double? cpuPercent;
  final int? memoryBytes;
  final List<NativeGatewayResourceAction> allowedActions;
  final List<NativeGatewayBlocker> blockers;
}

final class NativeGatewayPortLease {
  const NativeGatewayPortLease({
    required this.id,
    required this.projectId,
    required this.port,
    required this.purpose,
    required this.expiresAt,
  });

  final String id;
  final String projectId;
  final int port;
  final String purpose;
  final DateTime expiresAt;
}

final class NativeGatewayInventory {
  NativeGatewayInventory({
    required this.revision,
    required this.observedAt,
    required this.partial,
    required List<NativeGatewayProject> projects,
    required List<NativeGatewayResource> resources,
    required List<NativeGatewayPortLease> leases,
    required List<NativeGatewayBlocker> blockers,
  }) : projects = List.unmodifiable(projects),
       resources = List.unmodifiable(resources),
       leases = List.unmodifiable(leases),
       blockers = List.unmodifiable(blockers);

  final String revision;
  final DateTime observedAt;
  final bool partial;
  final List<NativeGatewayProject> projects;
  final List<NativeGatewayResource> resources;
  final List<NativeGatewayPortLease> leases;
  final List<NativeGatewayBlocker> blockers;
}

final class NativeGatewayEvent {
  const NativeGatewayEvent({
    required this.id,
    required this.kind,
    required this.code,
    required this.message,
    required this.occurredAt,
    this.projectId,
    this.resourceId,
  });

  final String id;
  final String? projectId;
  final String? resourceId;
  final String kind;
  final String code;
  final String message;
  final DateTime occurredAt;
}

final class NativeGatewayEventPage {
  NativeGatewayEventPage({
    required List<NativeGatewayEvent> events,
    required this.nextCursor,
    required this.hasMore,
  }) : events = List.unmodifiable(events);

  final List<NativeGatewayEvent> events;
  final String? nextCursor;
  final bool hasMore;
}

final class NativeGatewayLogPage {
  NativeGatewayLogPage({
    required List<String> lines,
    required this.nextCursor,
    required this.truncated,
  }) : lines = List.unmodifiable(lines);

  final List<String> lines;
  final String? nextCursor;
  final bool truncated;
}

final class NativeGatewayActionRequest {
  NativeGatewayActionRequest({String? reason})
    : reason = _optionalBoundedString(reason, 'reason', maxLength: 300);

  final String? reason;

  Map<String, Object?> toJson() => {if (reason != null) 'reason': reason};
}

final class NativeGatewayLeaseRequest {
  NativeGatewayLeaseRequest({
    required String projectId,
    required String purpose,
    int? preferredPort,
    int? ttlSeconds,
  }) : projectId = _requiredBoundedString(
         projectId,
         'projectId',
         maxLength: 256,
       ),
       purpose = _requiredBoundedString(purpose, 'purpose', maxLength: 120),
       preferredPort = _optionalPort(preferredPort, 'preferredPort'),
       ttlSeconds = ttlSeconds == null
           ? null
           : _boundedInt(ttlSeconds, 'ttlSeconds', minimum: 60, maximum: 86400);

  final String projectId;
  final String purpose;
  final int? preferredPort;
  final int? ttlSeconds;

  Map<String, Object?> toJson() => {
    'projectId': projectId,
    'purpose': purpose,
    if (preferredPort != null) 'preferredPort': preferredPort,
    if (ttlSeconds != null) 'ttlSeconds': ttlSeconds,
  };
}

enum NativeGatewayLifecycleTargetKind { project, server, container, worktree }

enum NativeGatewayLifecycleAction { archive, purge, restore }

final class NativeGatewayLifecyclePlanRequest {
  NativeGatewayLifecyclePlanRequest({
    required this.targetKind,
    required String targetId,
    required this.action,
    required String reason,
  }) : targetId = _requiredBoundedString(targetId, 'targetId', maxLength: 256),
       reason = _requiredBoundedString(reason, 'reason', maxLength: 300);

  final NativeGatewayLifecycleTargetKind targetKind;
  final String targetId;
  final NativeGatewayLifecycleAction action;
  final String reason;

  Map<String, Object?> toJson() => {
    'targetKind': targetKind.name,
    'targetId': targetId,
    'action': action.name,
    'reason': reason,
  };
}

final class NativeGatewayLifecycleApplyRequest {
  NativeGatewayLifecycleApplyRequest({
    required String planFingerprint,
    required String confirmationPhrase,
  }) : planFingerprint = _requiredBoundedString(
         planFingerprint,
         'planFingerprint',
         maxLength: 512,
       ),
       confirmationPhrase = _boundedString(
         confirmationPhrase,
         'confirmationPhrase',
         maxLength: 512,
       );

  final String planFingerprint;
  final String confirmationPhrase;

  Map<String, Object?> toJson() => {
    'planFingerprint': planFingerprint,
    'confirmationPhrase': confirmationPhrase,
  };
}

final class NativeGatewayLifecyclePlan {
  NativeGatewayLifecyclePlan({
    required this.id,
    required this.fingerprint,
    required this.targetId,
    required this.action,
    required List<String> effects,
    required List<String> retained,
    required List<String> deleted,
    required List<NativeGatewayBlocker> blockers,
    required this.confirmationPhrase,
    required this.expiresAt,
  }) : effects = List.unmodifiable(effects),
       retained = List.unmodifiable(retained),
       deleted = List.unmodifiable(deleted),
       blockers = List.unmodifiable(blockers);

  final String id;
  final String fingerprint;
  final String targetId;
  final NativeGatewayLifecycleAction action;
  final List<String> effects;
  final List<String> retained;
  final List<String> deleted;
  final List<NativeGatewayBlocker> blockers;
  final String confirmationPhrase;
  final DateTime expiresAt;
}

enum NativeGatewayOperationStatus {
  queued,
  running,
  succeeded,
  failed,
  timedOut,
  cancelled,
  partial,
  needsAttention,
}

enum NativeGatewayOperationTargetKind {
  project,
  server,
  container,
  database,
  route,
  portLease,
  worktree,
  unassignedResource,
}

enum NativeGatewayOperationTargetStatus {
  queued,
  running,
  succeeded,
  failed,
  timedOut,
  cancelled,
  blocked,
}

final class NativeGatewayOperationTargetResult {
  NativeGatewayOperationTargetResult({
    required this.targetId,
    required this.targetKind,
    required this.status,
    required this.message,
    required List<String> evidenceIds,
  }) : evidenceIds = List.unmodifiable(evidenceIds);

  final String targetId;
  final NativeGatewayOperationTargetKind targetKind;
  final NativeGatewayOperationTargetStatus status;
  final String message;
  final List<String> evidenceIds;
}

final class NativeGatewayProblem {
  NativeGatewayProblem({
    required this.type,
    required this.title,
    required this.status,
    required List<NativeGatewayBlocker> blockers,
    required Map<String, Object?> extensions,
    this.detail,
    this.instance,
    this.code,
    this.requestId,
  }) : blockers = List.unmodifiable(blockers),
       extensions = UnmodifiableMapView(Map.of(extensions));

  final String type;
  final String title;
  final int status;
  final String? detail;
  final String? instance;
  final String? code;
  final String? requestId;
  final List<NativeGatewayBlocker> blockers;
  final Map<String, Object?> extensions;
}

final class NativeGatewayOperation {
  NativeGatewayOperation({
    required this.id,
    required this.status,
    required this.partial,
    required this.needsAttention,
    required this.startedAt,
    required List<NativeGatewayOperationTargetResult> results,
    required List<NativeGatewayProblem> errors,
    this.finishedAt,
    this.resultRevision,
  }) : results = List.unmodifiable(results),
       errors = List.unmodifiable(errors);

  final String id;
  final NativeGatewayOperationStatus status;
  final bool partial;
  final bool needsAttention;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? resultRevision;
  final List<NativeGatewayOperationTargetResult> results;
  final List<NativeGatewayProblem> errors;

  bool get isTerminal => switch (status) {
    NativeGatewayOperationStatus.queued ||
    NativeGatewayOperationStatus.running => false,
    _ => true,
  };

  bool get isSuccessful =>
      status == NativeGatewayOperationStatus.succeeded &&
      !partial &&
      !needsAttention &&
      errors.isEmpty &&
      results.every(
        (result) =>
            result.status == NativeGatewayOperationTargetStatus.succeeded,
      );
}

final class NativeGatewayDocument<T> {
  const NativeGatewayDocument({required this.value, this.entityTag});

  final T value;
  final NativeGatewayEntityTag? entityTag;
}

sealed class NativeGatewayConditionalResult<T> {
  const NativeGatewayConditionalResult({required this.entityTag});

  final NativeGatewayEntityTag entityTag;
}

final class NativeGatewayModified<T> extends NativeGatewayConditionalResult<T> {
  const NativeGatewayModified({required this.value, required super.entityTag});

  final T value;
}

final class NativeGatewayNotModified<T>
    extends NativeGatewayConditionalResult<T> {
  const NativeGatewayNotModified({required super.entityTag});
}

String _boundedString(String value, String name, {required int maxLength}) {
  if (value.length > maxLength ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw ArgumentError('must be at most $maxLength safe characters', name);
  }
  return value;
}

String _requiredBoundedString(
  String value,
  String name, {
  required int maxLength,
}) {
  final bounded = _boundedString(value, name, maxLength: maxLength);
  if (bounded.trim().isEmpty) {
    throw ArgumentError('must not be empty', name);
  }
  return bounded;
}

String? _optionalBoundedString(
  String? value,
  String name, {
  required int maxLength,
}) {
  if (value == null) {
    return null;
  }
  return _boundedString(value, name, maxLength: maxLength);
}

int _boundedInt(
  int value,
  String name, {
  required int minimum,
  required int maximum,
}) {
  if (value < minimum || value > maximum) {
    throw ArgumentError.value(
      value,
      name,
      'must be between $minimum and $maximum',
    );
  }
  return value;
}

int? _optionalPort(int? value, String name) =>
    value == null ? null : _boundedInt(value, name, minimum: 1, maximum: 65535);
