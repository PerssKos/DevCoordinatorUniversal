import 'dart:collection';

import 'endpoint.dart';

enum CoordinatorCapability {
  inventoryRead,
  eventsRead,
  serverLifecycle,
  projectLifecycle,
  containerLifecycle,
  portLeases,
  logsRead,
  durableLifecycle,
}

/// Transport-neutral capability result.
///
/// A future native-v2 adapter maps its approved wire identifiers into this
/// enum. Unknown wire capabilities are ignored, and absence means unsupported.
final class CoordinatorCapabilities {
  CoordinatorCapabilities(Iterable<CoordinatorCapability> values)
    : values = Set.unmodifiable(values);

  final Set<CoordinatorCapability> values;

  bool supports(CoordinatorCapability capability) =>
      values.contains(capability);
}

final class CoordinatorMeta {
  CoordinatorMeta({
    required this.apiMajor,
    required this.connectionKind,
    required this.capabilities,
    this.serverVersion,
  });

  final int apiMajor;
  final CoordinatorConnectionKind connectionKind;
  final CoordinatorCapabilities capabilities;
  final String? serverVersion;

  bool supports(CoordinatorCapability capability) =>
      capabilities.supports(capability);
}

enum CoordinatorInventorySource { normalized, compatibility }

final class CoordinatorUsage {
  const CoordinatorUsage({
    this.sampledAt,
    this.cpuPercent,
    this.memoryBytes,
    this.networkRxBytes,
    this.networkTxBytes,
    this.blockReadBytes,
    this.blockWriteBytes,
  });

  final DateTime? sampledAt;
  final double? cpuPercent;
  final int? memoryBytes;
  final int? networkRxBytes;
  final int? networkTxBytes;
  final int? blockReadBytes;
  final int? blockWriteBytes;
}

final class CoordinatorProject {
  const CoordinatorProject({
    required this.id,
    required this.canonicalRoot,
    required this.displayName,
    required this.installationStatus,
    required this.startupFenced,
  });

  final String id;
  final String canonicalRoot;
  final String displayName;
  final String installationStatus;
  final bool startupFenced;
}

final class CoordinatorServer {
  CoordinatorServer({
    required this.id,
    required this.name,
    required this.status,
    required List<String> arguments,
    this.repoId,
    this.projectRoot,
    this.role,
    this.cwd,
    this.pid,
    this.host,
    this.port,
    this.healthClassification,
    this.healthOk,
    this.healthUrl,
    this.url,
    this.logPath,
    this.leaseId,
    this.usage,
    this.updatedAt,
  }) : arguments = List.unmodifiable(arguments);

  final String id;
  final String? repoId;
  final String? projectRoot;
  final String name;
  final String? role;
  final String? cwd;
  final List<String> arguments;
  final String status;
  final int? pid;
  final String? host;
  final int? port;
  final String? healthClassification;
  final bool? healthOk;
  final String? healthUrl;
  final String? url;
  final String? logPath;
  final String? leaseId;
  final CoordinatorUsage? usage;
  final DateTime? updatedAt;
}

final class CoordinatorPortBinding {
  const CoordinatorPortBinding({
    required this.containerPort,
    required this.protocol,
    this.hostAddress,
    this.hostPort,
  });

  final String? hostAddress;
  final int? hostPort;
  final int containerPort;
  final String protocol;
}

final class CoordinatorContainer {
  CoordinatorContainer({
    required this.id,
    required this.containerId,
    required this.name,
    required this.status,
    required List<CoordinatorPortBinding> ports,
    this.repoId,
    this.projectRoot,
    this.engineId,
    this.image,
    this.health,
    this.restartPolicy,
    this.portsSummary,
    this.usage,
    this.updatedAt,
  }) : ports = List.unmodifiable(ports);

  /// Normalized immutable Docker resource identity when available.
  final String id;
  final String containerId;
  final String? repoId;
  final String? projectRoot;
  final String? engineId;
  final String name;
  final String? image;
  final String status;
  final String? health;
  final String? restartPolicy;
  final List<CoordinatorPortBinding> ports;
  final String? portsSummary;
  final CoordinatorUsage? usage;
  final DateTime? updatedAt;
}

final class CoordinatorLease {
  const CoordinatorLease({
    required this.id,
    required this.port,
    required this.status,
    this.repoId,
    this.projectRoot,
    this.serverId,
    this.agent,
    this.purpose,
    this.owner,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String? repoId;
  final String? projectRoot;
  final String? serverId;
  final int port;
  final String status;
  final String? agent;
  final String? purpose;
  final String? owner;
  final DateTime? expiresAt;
  final DateTime? createdAt;
}

final class CoordinatorEvent {
  const CoordinatorEvent({
    required this.id,
    required this.kind,
    required this.occurredAt,
    this.repoId,
    this.projectRoot,
    this.code,
    this.message,
    this.sourceId,
  });

  final String id;
  final String? repoId;
  final String? projectRoot;
  final String? sourceId;
  final String kind;
  final String? code;
  final String? message;
  final DateTime occurredAt;
}

final class CoordinatorBackup {
  const CoordinatorBackup({
    required this.id,
    required this.status,
    required this.verificationStatus,
    required this.createdAt,
    this.repoId,
    this.projectRoot,
    this.databaseBindingId,
    this.dockerResourceId,
    this.containerId,
    this.containerName,
    this.databaseName,
    this.artifactPath,
    this.artifactSizeBytes,
    this.artifactSha256,
    this.manifestPath,
    this.format,
    this.verificationMode,
    this.verifiedAt,
  });

  final String id;
  final String? repoId;
  final String? projectRoot;
  final String? databaseBindingId;
  final String? dockerResourceId;
  final String? containerId;
  final String? containerName;
  final String? databaseName;
  final String? artifactPath;
  final int? artifactSizeBytes;
  final String? artifactSha256;
  final String? manifestPath;
  final String? format;
  final String status;
  final String verificationStatus;
  final String? verificationMode;
  final DateTime createdAt;
  final DateTime? verifiedAt;
}

final class CoordinatorUnassignedResource {
  CoordinatorUnassignedResource({
    required this.id,
    required this.resourceKind,
    required this.resourceId,
    required this.displayName,
    required this.reasonCode,
    required this.explanation,
    required List<String> observedBy,
    required this.canAttach,
    required this.canRetire,
    required this.lifecycleViolation,
    this.controller,
    this.immutableFingerprint,
    this.controlBindingId,
    this.ownershipFingerprint,
    this.recommendedNextStep,
  }) : observedBy = List.unmodifiable(observedBy);

  final String id;
  final String resourceKind;
  final String resourceId;
  final String displayName;
  final String reasonCode;
  final String explanation;
  final List<String> observedBy;
  final String? controller;
  final String? immutableFingerprint;
  final String? controlBindingId;
  final String? ownershipFingerprint;
  final bool canAttach;
  final bool canRetire;
  final bool lifecycleViolation;
  final String? recommendedNextStep;
}

final class CoordinatorInventory {
  CoordinatorInventory({
    required this.schemaVersion,
    required this.source,
    required List<CoordinatorProject> projects,
    required List<CoordinatorServer> servers,
    required List<CoordinatorContainer> containers,
    required List<CoordinatorLease> leases,
    required List<CoordinatorEvent> events,
    required List<CoordinatorBackup> backups,
    required List<CoordinatorUnassignedResource> unassignedResources,
    this.stateRevision,
    this.observationRevision,
    this.updatedAt,
  }) : projects = List.unmodifiable(projects),
       servers = List.unmodifiable(servers),
       containers = List.unmodifiable(containers),
       leases = List.unmodifiable(leases),
       events = List.unmodifiable(events),
       backups = List.unmodifiable(backups),
       unassignedResources = List.unmodifiable(unassignedResources);

  final int schemaVersion;
  final CoordinatorInventorySource source;
  final int? stateRevision;
  final int? observationRevision;
  final DateTime? updatedAt;
  final List<CoordinatorProject> projects;
  final List<CoordinatorServer> servers;
  final List<CoordinatorContainer> containers;
  final List<CoordinatorLease> leases;
  final List<CoordinatorEvent> events;
  final List<CoordinatorBackup> backups;
  final List<CoordinatorUnassignedResource> unassignedResources;
}

final class CoordinatorEventPage {
  CoordinatorEventPage({
    required List<CoordinatorEvent> events,
    required this.hasMore,
    this.nextCursor,
  }) : events = List.unmodifiable(events);

  final List<CoordinatorEvent> events;
  final String? nextCursor;
  final bool hasMore;
}

String _targetText(String value, String label) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, label, 'must not be empty');
  }
  return normalized;
}

final class CoordinatorActor {
  CoordinatorActor(String value) : value = _targetText(value, 'actor');

  final String value;
}

final class CoordinatorProjectTarget {
  CoordinatorProjectTarget({
    required String repoId,
    required String canonicalRoot,
  }) : repoId = _targetText(repoId, 'repoId'),
       canonicalRoot = _targetText(canonicalRoot, 'canonicalRoot');

  final String repoId;
  final String canonicalRoot;
}

final class CoordinatorServerTarget {
  CoordinatorServerTarget({
    required String id,
    required String repoId,
    required String projectRoot,
    required String name,
  }) : id = _targetText(id, 'id'),
       repoId = _targetText(repoId, 'repoId'),
       projectRoot = _targetText(projectRoot, 'projectRoot'),
       name = _targetText(name, 'name');

  final String id;
  final String repoId;
  final String projectRoot;
  final String name;
}

final class CoordinatorServerLaunchTarget {
  CoordinatorServerLaunchTarget({
    required String repoId,
    required String projectRoot,
    required String name,
  }) : repoId = _targetText(repoId, 'repoId'),
       projectRoot = _targetText(projectRoot, 'projectRoot'),
       name = _targetText(name, 'name');

  final String repoId;
  final String projectRoot;
  final String name;
}

final class CoordinatorContainerTarget {
  CoordinatorContainerTarget({
    required String resourceId,
    required String repoId,
    required String projectRoot,
    required String name,
    this.containerId,
  }) : resourceId = _targetText(resourceId, 'resourceId'),
       repoId = _targetText(repoId, 'repoId'),
       projectRoot = _targetText(projectRoot, 'projectRoot'),
       name = _targetText(name, 'name') {
    if (containerId != null) {
      _targetText(containerId!, 'containerId');
    }
  }

  final String resourceId;
  final String repoId;
  final String projectRoot;
  final String name;
  final String? containerId;
}

final class CoordinatorLeaseTarget {
  CoordinatorLeaseTarget({
    required String leaseId,
    required String repoId,
    required String projectRoot,
  }) : leaseId = _targetText(leaseId, 'leaseId'),
       repoId = _targetText(repoId, 'repoId'),
       projectRoot = _targetText(projectRoot, 'projectRoot');

  final String leaseId;
  final String repoId;
  final String projectRoot;
}

final class CoordinatorPortAssignmentTarget {
  CoordinatorPortAssignmentTarget({
    required String repoId,
    required String projectRoot,
    required String serverName,
  }) : repoId = _targetText(repoId, 'repoId'),
       projectRoot = _targetText(projectRoot, 'projectRoot'),
       serverName = _targetText(serverName, 'serverName');

  final String repoId;
  final String projectRoot;
  final String serverName;
}

enum CoordinatorLifecycleTargetKind {
  project('project'),
  server('server'),
  container('container'),
  worktree('worktree');

  const CoordinatorLifecycleTargetKind(this.wireValue);
  final String wireValue;
}

final class CoordinatorLifecycleTarget {
  CoordinatorLifecycleTarget({required this.kind, required String id})
    : id = _targetText(id, 'id');

  final CoordinatorLifecycleTargetKind kind;
  final String id;
}

enum CoordinatorResourceAction { start, stop, restart }

enum CoordinatorProjectAction { status, start, stop, restart }

final class CoordinatorPortRange {
  CoordinatorPortRange(this.first, this.last) {
    if (first < 1 || last > 65535 || first > last) {
      throw ArgumentError.value(
        '$first-$last',
        'range',
        'must be within 1-65535',
      );
    }
  }

  final int first;
  final int last;

  String get wireValue => '$first-$last';
}

final class CoordinatorServerStartRequest {
  CoordinatorServerStartRequest({
    required this.target,
    required this.actor,
    required List<String> arguments,
    required this.range,
    this.cwd,
    this.preferredPort,
    this.healthUrl,
    this.leaseId,
  }) : arguments = List.unmodifiable(
         arguments.map((value) {
           if (value.isEmpty) {
             throw ArgumentError.value(
               arguments,
               'arguments',
               'must not contain empty values',
             );
           }
           return value;
         }),
       ) {
    if (this.arguments.isEmpty) {
      throw ArgumentError.value(arguments, 'arguments', 'must not be empty');
    }
    if (preferredPort != null &&
        (preferredPort! < range.first || preferredPort! > range.last)) {
      throw ArgumentError.value(
        preferredPort,
        'preferredPort',
        'must be inside the requested range',
      );
    }
    if (leaseId != null) {
      _targetText(leaseId!, 'leaseId');
    }
  }

  final CoordinatorServerLaunchTarget target;
  final CoordinatorActor actor;
  final List<String> arguments;
  final CoordinatorPortRange range;
  final String? cwd;
  final int? preferredPort;
  final String? healthUrl;
  final String? leaseId;
}

final class CoordinatorPortLeaseRequest {
  CoordinatorPortLeaseRequest({
    required this.project,
    required this.server,
    required this.actor,
    required this.range,
    this.preferredPort,
    this.ttl,
    this.purpose,
  }) {
    if (server.repoId != project.repoId ||
        server.projectRoot != project.canonicalRoot) {
      throw ArgumentError.value(
        server,
        'server',
        'must belong to the exact requested project',
      );
    }
    if (preferredPort != null &&
        (preferredPort! < range.first || preferredPort! > range.last)) {
      throw ArgumentError.value(
        preferredPort,
        'preferredPort',
        'must be inside the requested range',
      );
    }
    if (ttl != null && ttl! <= Duration.zero) {
      throw ArgumentError.value(ttl, 'ttl', 'must be positive');
    }
  }

  final CoordinatorProjectTarget project;
  final CoordinatorServerTarget server;
  final CoordinatorActor actor;
  final CoordinatorPortRange range;
  final int? preferredPort;
  final Duration? ttl;
  final String? purpose;
}

final class CoordinatorActionResult {
  CoordinatorActionResult({
    required Map<String, Object?> data,
    this.ok,
    this.status,
  }) : data = UnmodifiableMapView(data);

  final bool? ok;
  final String? status;
  final Map<String, Object?> data;
}

final class CoordinatorLogResult {
  const CoordinatorLogResult({
    required this.text,
    required this.truncated,
    this.stdout,
    this.stderr,
    this.exitCode,
  });

  final String text;
  final String? stdout;
  final String? stderr;
  final int? exitCode;
  final bool truncated;
}

final class CoordinatorArchive {
  CoordinatorArchive({
    required this.target,
    required this.displayName,
    required this.restorable,
    required this.removable,
    required List<String> effects,
    required List<String> retained,
    required List<String> blockers,
    this.status,
    this.archivedAt,
    this.reason,
    this.actor,
    this.parentId,
  }) : effects = List.unmodifiable(effects),
       retained = List.unmodifiable(retained),
       blockers = List.unmodifiable(blockers);

  final CoordinatorLifecycleTarget target;
  final String displayName;
  final String? status;
  final bool restorable;
  final bool removable;
  final DateTime? archivedAt;
  final String? reason;
  final String? actor;
  final String? parentId;
  final List<String> effects;
  final List<String> retained;
  final List<String> blockers;
}

enum CoordinatorLifecyclePlanAction { archive, purge }

final class CoordinatorLifecyclePlan {
  CoordinatorLifecyclePlan({
    required this.id,
    required this.fingerprint,
    required this.target,
    required this.action,
    required List<String> effects,
    required List<String> retained,
    required List<String> deleted,
    required List<String> blockers,
    this.confirmationPhrase,
  }) : effects = List.unmodifiable(effects),
       retained = List.unmodifiable(retained),
       deleted = List.unmodifiable(deleted),
       blockers = List.unmodifiable(blockers);

  final String id;
  final String fingerprint;
  final CoordinatorLifecycleTarget target;
  final CoordinatorLifecyclePlanAction action;
  final List<String> effects;
  final List<String> retained;
  final List<String> deleted;
  final List<String> blockers;
  final String? confirmationPhrase;
}

final class CoordinatorLifecycleApply {
  CoordinatorLifecycleApply({
    required String planId,
    required String planFingerprint,
    this.confirmationPhrase = '',
  }) : planId = _targetText(planId, 'planId'),
       planFingerprint = _targetText(planFingerprint, 'planFingerprint');

  final String planId;
  final String planFingerprint;
  final String confirmationPhrase;
}
