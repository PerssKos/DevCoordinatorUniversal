import 'errors.dart';
import 'json_support.dart';
import 'models.dart';

final class CoordinatorInventoryParser {
  const CoordinatorInventoryParser();

  CoordinatorInventory parse(Object? json) {
    final root = JsonReader.root(json);
    final schemaVersion = root.optionalInt('schema_version') ?? 1;
    if (schemaVersion == 2) {
      return _parseNormalized(root);
    }
    if (schemaVersion != 1) {
      throw CoordinatorProtocolException(
        'Unsupported inventory schema version $schemaVersion.',
        path: r'$.schema_version',
      );
    }
    final compatibility = root.optionalObject('v1_compatibility') ?? root;
    return _parseCompatibility(
      compatibility,
      schemaVersion: schemaVersion,
      unassignedRoot: root,
    );
  }

  CoordinatorEventPage parseEventPage(Object? json) {
    final root = JsonReader.root(json);
    final events = _objects(
      root.requiredList('events'),
      r'$.events',
    ).map((row) => _parseEvent(row, normalized: true)).toList(growable: false);
    _requireUnique(events, (item) => item.id, r'$.events');
    return CoordinatorEventPage(
      events: events,
      nextCursor: root.optionalString('next_cursor'),
      hasMore: root.optionalBool('has_more') ?? false,
    );
  }

  CoordinatorLease parseLease(Object? json) =>
      _parseLease(JsonReader.root(json), normalized: false);

  List<CoordinatorArchive> parseArchives(Object? json) {
    final root = JsonReader.root(json);
    return _objects(
      root.requiredList('archives'),
      r'$.archives',
    ).map(_parseArchive).toList(growable: false);
  }

  CoordinatorLifecyclePlan parseLifecyclePlan(Object? json) {
    final root = JsonReader.root(json);
    final plan = root.optionalObject('plan') ?? root;
    final rawKind = plan.optionalString('target_kind') ?? 'project';
    final kind = _lifecycleKind(rawKind, '${plan.path}.target_kind');
    final rawAction = plan.optionalString('action') ?? 'archive';
    final action = switch (rawAction) {
      'archive' => CoordinatorLifecyclePlanAction.archive,
      'purge' => CoordinatorLifecyclePlanAction.purge,
      _ => throw CoordinatorProtocolException(
        'Unsupported lifecycle plan action $rawAction.',
        path: '${plan.path}.action',
      ),
    };
    final fingerprint =
        plan.optionalString('plan_fingerprint') ??
        plan.optionalString('fingerprint');
    if (fingerprint == null || fingerprint.trim().isEmpty) {
      throw CoordinatorProtocolException(
        'Lifecycle plan is missing its fingerprint.',
        path: '${plan.path}.plan_fingerprint',
      );
    }
    final targetId =
        plan.optionalString('target_id') ??
        plan.optionalString('repo_id') ??
        plan.optionalString('resource_id');
    if (targetId == null || targetId.trim().isEmpty) {
      throw CoordinatorProtocolException(
        'Lifecycle plan is missing its exact target identity.',
        path: '${plan.path}.target_id',
      );
    }
    return CoordinatorLifecyclePlan(
      id: plan.requiredString('plan_id'),
      fingerprint: fingerprint,
      target: CoordinatorLifecycleTarget(kind: kind, id: targetId),
      action: action,
      effects: _descriptions(plan, 'effects'),
      retained: _descriptions(plan, 'retained'),
      deleted: _descriptions(plan, 'deleted'),
      blockers: _descriptions(plan, 'blockers'),
      confirmationPhrase: plan.optionalString('confirmation_phrase'),
    );
  }

  CoordinatorInventory _parseNormalized(JsonReader root) {
    final store = root.optionalObject('store');
    final compatibility = root.optionalObject('v1_compatibility');
    final projects = _objects(
      root.requiredList('repositories'),
      r'$.repositories',
    ).map(_parseNormalizedProject).toList(growable: false);
    _requireUnique(projects, (item) => item.id, r'$.repositories');
    final projectsById = {for (final item in projects) item.id: item};

    final memberships = _objects(
      root.requiredList('memberships'),
      r'$.memberships',
    );
    final repoIdsByContainer = <String, Set<String>>{};
    for (final membership in memberships) {
      final kind = membership.requiredString('resource_kind');
      if (kind != 'container') {
        continue;
      }
      repoIdsByContainer
          .putIfAbsent(
            membership.requiredString('host_resource_id'),
            () => <String>{},
          )
          .add(membership.requiredString('repo_id'));
    }

    final resources = root.requiredObject('resources');
    final observations = root.requiredObject('observations');
    final serverObservations = _index(
      _objects(
        observations.requiredList('servers'),
        '${observations.path}.servers',
      ),
      (row) => row.requiredString('server_definition_id'),
      '${observations.path}.servers',
    );
    final containerObservations = _index(
      _objects(
        observations.requiredList('docker'),
        '${observations.path}.docker',
      ),
      (row) => row.requiredString('docker_resource_id'),
      '${observations.path}.docker',
    );
    final telemetry = _latestTelemetry(
      _objects(
        observations.optionalList('telemetry'),
        '${observations.path}.telemetry',
      ),
    );
    final compatibilityServers = compatibility == null
        ? <String, JsonReader>{}
        : _index(
            _objects(
              compatibility.optionalList('servers'),
              '${compatibility.path}.servers',
            ),
            (row) => row.requiredString('id'),
            '${compatibility.path}.servers',
          );
    final compatibilityContainers = compatibility == null
        ? <String, JsonReader>{}
        : _index(
            _objects(
              compatibility
                      .optionalObject('docker')
                      ?.optionalList('containers') ??
                  const [],
              '${compatibility.path}.docker.containers',
            ),
            (row) =>
                row.optionalString('host_resource_id') ??
                row.requiredString('id'),
            '${compatibility.path}.docker.containers',
          );

    final leases = _objects(root.requiredList('leases'), r'$.leases')
        .map(
          (row) => _parseLease(row, normalized: true, projects: projectsById),
        )
        .toList(growable: false);
    _requireUnique(leases, (item) => item.id, r'$.leases');
    final activeLeaseByServer = <String, CoordinatorLease>{};
    for (final lease in leases) {
      if (lease.serverId != null && lease.status == 'active') {
        activeLeaseByServer.putIfAbsent(lease.serverId!, () => lease);
      }
    }

    final servers =
        _objects(resources.requiredList('servers'), '${resources.path}.servers')
            .map((definition) {
              final id = definition.requiredString('server_definition_id');
              final repoId = definition.requiredString('repo_id');
              final project = projectsById[repoId];
              if (project == null) {
                throw CoordinatorProtocolException(
                  'Server $id references unknown repository $repoId.',
                  path: '${definition.path}.repo_id',
                );
              }
              final observation = serverObservations[id];
              final legacy = compatibilityServers[id];
              final legacyHealth = legacy?.optionalObject('health');
              return CoordinatorServer(
                id: id,
                repoId: repoId,
                projectRoot: project.canonicalRoot,
                name: definition.requiredString('name'),
                role: definition.optionalString('role'),
                cwd: definition.requiredString('cwd'),
                arguments: definition.optionalStringList('arguments'),
                status:
                    observation?.optionalString('lifecycle') ??
                    legacy?.optionalString('status') ??
                    'unobserved',
                pid:
                    observation?.optionalInt('pid') ??
                    legacy?.optionalInt('pid'),
                host:
                    observation?.optionalString('listener_host') ??
                    legacy?.optionalString('host'),
                port:
                    observation?.optionalInt('listener_port') ??
                    legacy?.optionalInt('port') ??
                    activeLeaseByServer[id]?.port,
                healthClassification:
                    observation?.optionalString('health_classification') ??
                    legacyHealth?.optionalString('classification'),
                healthOk:
                    observation?.optionalBool('health_ok') ??
                    legacyHealth?.optionalBool('ok'),
                healthUrl:
                    definition.optionalString('health_url_template') ??
                    legacy?.optionalString('health_url'),
                url: legacy?.optionalString('url'),
                logPath:
                    definition.optionalString('log_path') ??
                    legacy?.optionalString('log_path'),
                leaseId:
                    activeLeaseByServer[id]?.id ??
                    legacy?.optionalString('lease_id'),
                usage:
                    telemetry['server:$id'] ??
                    _parseCompatibilityUsage(
                      legacy?.optionalObject('process_usage'),
                    ),
                updatedAt:
                    observation?.optionalDate('sampled_at') ??
                    legacy?.optionalDate('updated_at'),
              );
            })
            .toList(growable: false);
    _requireUnique(servers, (item) => item.id, '${resources.path}.servers');
    _requireUnique(
      servers,
      (item) => '${item.repoId}\u0000${item.name}',
      '${resources.path}.servers',
    );

    final portsByContainer = <String, List<CoordinatorPortBinding>>{};
    for (final row in _objects(
      resources.optionalList('docker_ports'),
      '${resources.path}.docker_ports',
    )) {
      final id = row.requiredString('docker_resource_id');
      portsByContainer
          .putIfAbsent(id, () => [])
          .add(
            CoordinatorPortBinding(
              hostAddress: row.optionalString('host_address'),
              hostPort: row.optionalInt('host_port'),
              containerPort: row.requiredInt('container_port'),
              protocol: row.requiredString('protocol'),
            ),
          );
    }
    final containers =
        _objects(resources.requiredList('docker'), '${resources.path}.docker')
            .map((resource) {
              final id = resource.requiredString('docker_resource_id');
              final membershipRepoIds =
                  repoIdsByContainer[id] ?? const <String>{};
              final repoId = membershipRepoIds.length == 1
                  ? membershipRepoIds.single
                  : null;
              final project = repoId == null ? null : projectsById[repoId];
              if (repoId != null && project == null) {
                throw CoordinatorProtocolException(
                  'Container $id references unknown repository $repoId.',
                  path: '${resource.path}.docker_resource_id',
                );
              }
              final observation = containerObservations[id];
              final legacy = compatibilityContainers[id];
              return CoordinatorContainer(
                id: id,
                containerId: resource.requiredString('full_container_id'),
                repoId: repoId,
                projectRoot: project?.canonicalRoot,
                engineId: resource.requiredString('engine_id'),
                name: resource.requiredString('current_name'),
                image: resource.optionalString('image'),
                status:
                    observation?.optionalString('lifecycle') ??
                    legacy?.optionalString('status') ??
                    'unobserved',
                health:
                    observation?.optionalString('health') ??
                    legacy?.optionalString('health'),
                restartPolicy:
                    observation?.optionalString('restart_policy') ??
                    legacy?.optionalString('restart_policy'),
                ports: portsByContainer[id] ?? const [],
                portsSummary: legacy?.optionalString('ports'),
                usage:
                    telemetry['docker:$id'] ??
                    telemetry['container:$id'] ??
                    _parseCompatibilityUsage(legacy?.optionalObject('stats')),
                updatedAt:
                    observation?.optionalDate('sampled_at') ??
                    legacy?.optionalDate('sampled_at'),
              );
            })
            .toList(growable: false);
    _requireUnique(containers, (item) => item.id, '${resources.path}.docker');

    final events = _objects(
      root.requiredList('events'),
      r'$.events',
    ).map((row) => _parseEvent(row, normalized: true)).toList(growable: false);
    _requireUnique(events, (item) => item.id, r'$.events');
    final backups =
        _objects(root.requiredList('database_backups'), r'$.database_backups')
            .map(
              (row) =>
                  _parseBackup(row, normalized: true, projects: projectsById),
            )
            .toList(growable: false);
    _requireUnique(backups, (item) => item.id, r'$.database_backups');
    final unassigned = _objects(
      root.requiredList('unassigned_resources'),
      r'$.unassigned_resources',
    ).map(_parseUnassigned).toList(growable: false);
    _requireUnique(unassigned, (item) => item.id, r'$.unassigned_resources');

    return CoordinatorInventory(
      schemaVersion: 2,
      source: CoordinatorInventorySource.normalized,
      stateRevision: store?.optionalInt('state_revision'),
      observationRevision: store?.optionalInt('observation_revision'),
      updatedAt: store?.optionalDate('updated_at'),
      projects: projects,
      servers: servers,
      containers: containers,
      leases: leases,
      events: events,
      backups: backups,
      unassignedResources: unassigned,
    );
  }

  CoordinatorInventory _parseCompatibility(
    JsonReader compatibility, {
    required int schemaVersion,
    required JsonReader unassignedRoot,
  }) {
    final projects = <CoordinatorProject>[];
    for (final row in _objects(
      compatibility.optionalList('project_usage'),
      '${compatibility.path}.project_usage',
    )) {
      final root = row.requiredString('project');
      projects.add(
        CoordinatorProject(
          id: row.optionalString('usage_key') ?? 'path:$root',
          canonicalRoot: root,
          displayName:
              row.optionalString('display_name') ?? _lastPathComponent(root),
          installationStatus: 'active',
          startupFenced: false,
        ),
      );
    }
    _requireUnique(
      projects,
      (item) => item.canonicalRoot,
      '${compatibility.path}.project_usage',
    );
    final projectsByRoot = {
      for (final project in projects) project.canonicalRoot: project,
    };

    final servers = _objects(
      compatibility.optionalList('servers'),
      '${compatibility.path}.servers',
    ).map((row) => _parseCompatibilityServer(row)).toList(growable: false);
    _requireUnique(servers, (item) => item.id, '${compatibility.path}.servers');
    for (final server in servers) {
      final projectRoot = server.projectRoot;
      if (projectRoot != null && !projectsByRoot.containsKey(projectRoot)) {
        final project = CoordinatorProject(
          id: 'path:$projectRoot',
          canonicalRoot: projectRoot,
          displayName: _lastPathComponent(projectRoot),
          installationStatus: 'active',
          startupFenced: false,
        );
        projects.add(project);
        projectsByRoot[projectRoot] = project;
      }
    }

    final docker = compatibility.optionalObject('docker');
    final containers = _objects(
      docker?.optionalList('containers') ?? const [],
      '${compatibility.path}.docker.containers',
    ).map(_parseCompatibilityContainer).toList(growable: false);
    _requireUnique(
      containers,
      (item) => item.id,
      '${compatibility.path}.docker.containers',
    );
    for (final container in containers) {
      final projectRoot = container.projectRoot;
      if (projectRoot != null && !projectsByRoot.containsKey(projectRoot)) {
        final project = CoordinatorProject(
          id: 'path:$projectRoot',
          canonicalRoot: projectRoot,
          displayName: _lastPathComponent(projectRoot),
          installationStatus: 'active',
          startupFenced: false,
        );
        projects.add(project);
        projectsByRoot[projectRoot] = project;
      }
    }

    final leases = _objects(
      compatibility.optionalList('leases'),
      '${compatibility.path}.leases',
    ).map((row) => _parseLease(row, normalized: false)).toList(growable: false);
    final events = _objects(
      compatibility.optionalList('recent_events'),
      '${compatibility.path}.recent_events',
    ).map((row) => _parseEvent(row, normalized: false)).toList(growable: false);
    final backups =
        _objects(
              compatibility.optionalList('backups'),
              '${compatibility.path}.backups',
            )
            .map((row) => _parseBackup(row, normalized: false))
            .toList(growable: false);
    final unassigned = _objects(
      unassignedRoot.optionalList('unassigned_resources'),
      '${unassignedRoot.path}.unassigned_resources',
    ).map(_parseUnassigned).toList(growable: false);

    return CoordinatorInventory(
      schemaVersion: schemaVersion,
      source: CoordinatorInventorySource.compatibility,
      projects: projects,
      servers: servers,
      containers: containers,
      leases: leases,
      events: events,
      backups: backups,
      unassignedResources: unassigned,
    );
  }

  CoordinatorProject _parseNormalizedProject(JsonReader row) =>
      CoordinatorProject(
        id: row.requiredString('repo_id'),
        canonicalRoot: row.requiredString('canonical_root'),
        displayName: row.requiredString('display_name'),
        installationStatus:
            row.optionalString('installation_status') ?? 'unknown',
        startupFenced: row.optionalBool('startup_fenced') ?? false,
      );

  CoordinatorServer _parseCompatibilityServer(JsonReader row) {
    final health = row.optionalObject('health');
    return CoordinatorServer(
      id: row.requiredString('id'),
      projectRoot: row.optionalString('project'),
      name: row.requiredString('name'),
      role: row.optionalString('role'),
      cwd: row.optionalString('cwd'),
      arguments: row.optionalStringList('argv'),
      status: row.optionalString('status') ?? 'unknown',
      pid: row.optionalInt('pid'),
      host: row.optionalString('host'),
      port: row.optionalInt('port'),
      healthClassification: health?.optionalString('classification'),
      healthOk: health?.optionalBool('ok'),
      healthUrl: row.optionalString('health_url'),
      url: row.optionalString('url'),
      logPath: row.optionalString('log_path'),
      leaseId: row.optionalString('lease_id'),
      usage: _parseCompatibilityUsage(row.optionalObject('process_usage')),
      updatedAt: row.optionalDate('updated_at'),
    );
  }

  CoordinatorContainer _parseCompatibilityContainer(JsonReader row) {
    final containerId = row.requiredString('id');
    return CoordinatorContainer(
      id: row.optionalString('host_resource_id') ?? containerId,
      containerId: containerId,
      projectRoot: row.optionalString('project'),
      name: row.requiredString('name'),
      image: row.optionalString('image'),
      status: row.optionalString('status') ?? 'unknown',
      health: row.optionalString('health'),
      restartPolicy: row.optionalString('restart_policy'),
      ports: const [],
      portsSummary: row.optionalString('ports'),
      usage: _parseCompatibilityUsage(row.optionalObject('stats')),
      updatedAt: row.optionalDate('sampled_at'),
    );
  }

  CoordinatorLease _parseLease(
    JsonReader row, {
    required bool normalized,
    Map<String, CoordinatorProject>? projects,
  }) {
    final repoId = normalized ? row.requiredString('repo_id') : null;
    final project = repoId == null ? null : projects?[repoId];
    if (repoId != null && projects != null && project == null) {
      throw CoordinatorProtocolException(
        'Lease references unknown repository $repoId.',
        path: '${row.path}.repo_id',
      );
    }
    return CoordinatorLease(
      id: normalized
          ? row.requiredString('lease_id')
          : row.requiredString('id'),
      repoId: repoId,
      projectRoot:
          project?.canonicalRoot ??
          (normalized ? null : row.optionalString('project')),
      serverId: normalized
          ? row.optionalString('server_definition_id')
          : row.optionalString('server_id'),
      port: row.requiredInt('port'),
      status: row.optionalString('status') ?? 'active',
      agent: row.optionalString('agent'),
      purpose: row.optionalString('purpose'),
      owner: row.optionalString('owner'),
      expiresAt: row.optionalDate('expires_at'),
      createdAt: row.optionalDate('created_at'),
    );
  }

  CoordinatorEvent _parseEvent(JsonReader row, {required bool normalized}) =>
      CoordinatorEvent(
        id: normalized
            ? row.requiredString('event_id')
            : row.requiredString('id'),
        repoId: normalized ? row.optionalString('repo_id') : null,
        projectRoot: normalized ? null : row.optionalString('project'),
        sourceId: normalized ? row.optionalString('source_id') : null,
        kind: normalized
            ? row.requiredString('event_kind')
            : row.requiredString('type'),
        code: row.optionalString('code'),
        message: row.optionalString('message'),
        occurredAt: normalized
            ? row.requiredDate('occurred_at')
            : row.requiredDate('at'),
      );

  CoordinatorBackup _parseBackup(
    JsonReader row, {
    required bool normalized,
    Map<String, CoordinatorProject>? projects,
  }) {
    final repoId = normalized ? row.optionalString('repo_id') : null;
    return CoordinatorBackup(
      id: normalized
          ? row.requiredString('database_backup_id')
          : row.requiredString('id'),
      repoId: repoId,
      projectRoot: normalized
          ? (repoId == null ? null : projects?[repoId]?.canonicalRoot)
          : row.optionalString('project'),
      databaseBindingId: normalized
          ? row.optionalString('database_binding_id')
          : null,
      dockerResourceId: normalized
          ? row.optionalString('docker_resource_id')
          : null,
      containerId: normalized
          ? row.requiredString('source_container_id')
          : row.optionalString('container_id'),
      containerName: normalized ? null : row.optionalString('container'),
      databaseName: normalized
          ? row.optionalString('source_database_name')
          : row.optionalString('database'),
      artifactPath: normalized
          ? row.optionalString('artifact_path')
          : row.optionalString('path'),
      artifactSizeBytes: normalized
          ? row.optionalInt('artifact_size_bytes')
          : row.optionalInt('size'),
      artifactSha256: normalized
          ? row.optionalString('artifact_sha256')
          : row.optionalString('sha256'),
      manifestPath: normalized
          ? row.optionalString('manifest_path')
          : row.optionalString('manifest'),
      format: normalized
          ? row.optionalString('backup_format')
          : row.optionalString('format'),
      status: row.optionalString('status') ?? 'unknown',
      verificationStatus:
          row.optionalString('verification_status') ?? 'unknown',
      verificationMode: row.optionalString('verification_mode'),
      createdAt: row.requiredDate('created_at'),
      verifiedAt: row.optionalDate('verified_at'),
    );
  }

  CoordinatorUnassignedResource _parseUnassigned(JsonReader row) =>
      CoordinatorUnassignedResource(
        id: row.requiredString('unassigned_id'),
        resourceKind: row.requiredString('resource_kind'),
        resourceId: row.requiredString('resource_id'),
        displayName: row.requiredString('display_name'),
        reasonCode: row.requiredString('reason_code'),
        explanation:
            row.optionalString('explanation') ??
            'Repository attribution is unavailable.',
        observedBy: row.optionalStringList('observed_by'),
        controller: row.optionalString('controller'),
        immutableFingerprint: row.optionalString('immutable_fingerprint'),
        controlBindingId: row.optionalString('control_binding_id'),
        ownershipFingerprint: row.optionalString('ownership_fingerprint'),
        canAttach: row.optionalBool('can_attach') ?? false,
        canRetire: row.optionalBool('can_retire') ?? false,
        lifecycleViolation: row.optionalBool('lifecycle_violation') ?? false,
        recommendedNextStep: row.optionalString('recommended_next_step'),
      );

  CoordinatorUsage? _parseCompatibilityUsage(JsonReader? row) {
    if (row == null) {
      return null;
    }
    return CoordinatorUsage(
      sampledAt:
          row.optionalDate('sampled_at') ?? row.optionalDate('timestamp'),
      cpuPercent: row.optionalDouble('cpu_percent'),
      memoryBytes:
          row.optionalInt('memory_bytes') ??
          row.optionalInt('memory_usage_bytes') ??
          row.optionalInt('rss_bytes'),
      networkRxBytes: row.optionalInt('network_rx_bytes'),
      networkTxBytes: row.optionalInt('network_tx_bytes'),
      blockReadBytes: row.optionalInt('block_read_bytes'),
      blockWriteBytes: row.optionalInt('block_write_bytes'),
    );
  }

  Map<String, CoordinatorUsage> _latestTelemetry(List<JsonReader> rows) {
    final result = <String, CoordinatorUsage>{};
    final timestamps = <String, DateTime>{};
    for (final row in rows) {
      final kind = row.requiredString('host_resource_kind');
      final id = row.requiredString('host_resource_id');
      final key = '$kind:$id';
      final sampledAt = row.requiredDate('sampled_at');
      final previous = timestamps[key];
      if (previous != null && !sampledAt.isAfter(previous)) {
        continue;
      }
      timestamps[key] = sampledAt;
      result[key] = CoordinatorUsage(
        sampledAt: sampledAt,
        cpuPercent: row.optionalDouble('cpu_percent'),
        memoryBytes: row.optionalInt('memory_bytes'),
        networkRxBytes: row.optionalInt('network_rx_bytes'),
        networkTxBytes: row.optionalInt('network_tx_bytes'),
        blockReadBytes: row.optionalInt('block_read_bytes'),
        blockWriteBytes: row.optionalInt('block_write_bytes'),
      );
    }
    return result;
  }

  CoordinatorArchive _parseArchive(JsonReader row) {
    final kind = _lifecycleKind(
      row.requiredString('target_kind'),
      '${row.path}.target_kind',
    );
    return CoordinatorArchive(
      target: CoordinatorLifecycleTarget(
        kind: kind,
        id: row.requiredString('target_id'),
      ),
      displayName: row.requiredString('display_name'),
      status: row.optionalString('status'),
      restorable: row.optionalBool('restorable') ?? false,
      removable: row.optionalBool('removable') ?? false,
      archivedAt: row.optionalDate('archived_at'),
      reason: row.optionalString('reason'),
      actor: row.optionalString('actor'),
      parentId: row.optionalString('parent'),
      effects: _descriptions(row, 'effects'),
      retained: _descriptions(row, 'retained'),
      blockers: _descriptions(row, 'blockers'),
    );
  }

  CoordinatorLifecycleTargetKind _lifecycleKind(String raw, String path) =>
      switch (raw) {
        'project' || 'repository' => CoordinatorLifecycleTargetKind.project,
        'server' => CoordinatorLifecycleTargetKind.server,
        'container' => CoordinatorLifecycleTargetKind.container,
        'worktree' => CoordinatorLifecycleTargetKind.worktree,
        _ => throw CoordinatorProtocolException(
          'Unsupported lifecycle target kind $raw.',
          path: path,
        ),
      };

  List<String> _descriptions(JsonReader row, String key) {
    final values = row.optionalList(key);
    return values.indexed
        .map((entry) {
          final value = entry.$2;
          if (value is String) {
            return value;
          }
          if (value is Map) {
            final item = JsonReader(
              JsonReader.object(value, '${row.path}.$key[${entry.$1}]'),
              '${row.path}.$key[${entry.$1}]',
            );
            final description =
                item.optionalString('description') ??
                item.optionalString('message') ??
                item.optionalString('kind');
            if (description == null) {
              throw CoordinatorProtocolException(
                'Lifecycle detail has no description.',
                path: item.path,
              );
            }
            return description;
          }
          throw CoordinatorProtocolException(
            'Expected a lifecycle description at ${row.path}.$key[${entry.$1}].',
            path: '${row.path}.$key[${entry.$1}]',
          );
        })
        .toList(growable: false);
  }

  List<JsonReader> _objects(List<Object?> values, String path) => values.indexed
      .map(
        (entry) => JsonReader(
          JsonReader.object(entry.$2, '$path[${entry.$1}]'),
          '$path[${entry.$1}]',
        ),
      )
      .toList(growable: false);

  Map<String, JsonReader> _index(
    List<JsonReader> rows,
    String Function(JsonReader) key,
    String path,
  ) {
    final result = <String, JsonReader>{};
    for (final row in rows) {
      final id = key(row);
      if (result.containsKey(id)) {
        throw CoordinatorProtocolException(
          'Duplicate identity $id at $path.',
          path: path,
        );
      }
      result[id] = row;
    }
    return result;
  }

  void _requireUnique<T>(
    Iterable<T> values,
    String Function(T) key,
    String path,
  ) {
    final seen = <String>{};
    for (final value in values) {
      final id = key(value);
      if (!seen.add(id)) {
        throw CoordinatorProtocolException(
          'Duplicate identity $id at $path.',
          path: path,
        );
      }
    }
  }

  String _lastPathComponent(String path) {
    final pieces = path.split('/').where((item) => item.isNotEmpty).toList();
    return pieces.isEmpty ? path : pieces.last;
  }
}
