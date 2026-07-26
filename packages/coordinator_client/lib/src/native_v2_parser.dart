import 'errors.dart';
import 'json_support.dart';
import 'native_v2_models.dart';

/// Strict parser for the non-deferred Native Gateway v2 schemas.
///
/// Objects declared with `additionalProperties: false` reject unknown fields.
/// Closed enums, uniqueness constraints, numeric bounds, and RFC 3339
/// timestamps are validated before a DTO is returned.
final class NativeGatewayV2Parser {
  const NativeGatewayV2Parser();

  NativeGatewayMeta parseMeta(Object? json, {required Uri gatewayEndpoint}) {
    final root = _V2Object.root(json)
      ..only(const {
        'contractVersion',
        'serverVersion',
        'minimumClientVersion',
        'issuer',
        'authorizationEndpoint',
        'tokenEndpoint',
        'revocationEndpoint',
        'publicClientId',
        'pkceMethods',
        'capabilities',
      });
    final contractVersion = root.string('contractVersion');
    if (contractVersion != '2.0') {
      throw CoordinatorProtocolException(
        'Unsupported native gateway contract version.',
        path: '${root.path}.contractVersion',
      );
    }
    final serverVersion = root.string('serverVersion');
    final minimumClientVersion = root.string('minimumClientVersion');
    for (final entry in {
      'serverVersion': serverVersion,
      'minimumClientVersion': minimumClientVersion,
    }.entries) {
      if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+').hasMatch(entry.value)) {
        throw CoordinatorProtocolException(
          'Expected a semantic version at ${root.path}.${entry.key}.',
          path: '${root.path}.${entry.key}',
        );
      }
    }

    final expectedGateway = _httpsEndpoint(
      gatewayEndpoint.toString(),
      r'$.gatewayEndpoint',
    );
    final issuer = _httpsEndpoint(root.string('issuer'), '${root.path}.issuer');
    if (!_sameOrigin(issuer, expectedGateway)) {
      throw CoordinatorProtocolException(
        'Native gateway issuer does not match the requested gateway origin.',
        path: '${root.path}.issuer',
      );
    }
    final authorizationEndpoint = _sameOriginOAuthEndpoint(
      root.string('authorizationEndpoint'),
      '${root.path}.authorizationEndpoint',
      issuer,
    );
    final tokenEndpoint = _sameOriginOAuthEndpoint(
      root.string('tokenEndpoint'),
      '${root.path}.tokenEndpoint',
      issuer,
    );
    final revocationEndpoint = _sameOriginOAuthEndpoint(
      root.string('revocationEndpoint'),
      '${root.path}.revocationEndpoint',
      issuer,
    );
    final publicClientId = root.nonEmptyString('publicClientId');
    if (publicClientId.length > 256 ||
        publicClientId.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
      throw CoordinatorProtocolException(
        'Invalid OAuth public client identifier.',
        path: '${root.path}.publicClientId',
      );
    }
    final wirePkceMethods = root.uniqueStrings('pkceMethods');
    if (wirePkceMethods.length != 1 ||
        !wirePkceMethods.contains(NativeGatewayPkceMethod.s256.wireValue)) {
      throw CoordinatorProtocolException(
        'Native gateway must advertise only PKCE S256.',
        path: '${root.path}.pkceMethods',
      );
    }

    final wireCapabilities = root.uniqueStrings('capabilities');
    final known = <NativeGatewayCapability>{};
    for (final wireValue in wireCapabilities) {
      if (!RegExp(
        r'^[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+$',
      ).hasMatch(wireValue)) {
        throw CoordinatorProtocolException(
          'Invalid capability identifier.',
          path: '${root.path}.capabilities',
        );
      }
      final capability = NativeGatewayCapability.fromWire(wireValue);
      if (capability != null) {
        known.add(capability);
      }
    }
    return NativeGatewayMeta(
      contractVersion: contractVersion,
      serverVersion: serverVersion,
      minimumClientVersion: minimumClientVersion,
      issuer: issuer,
      authorizationEndpoint: authorizationEndpoint,
      tokenEndpoint: tokenEndpoint,
      revocationEndpoint: revocationEndpoint,
      publicClientId: publicClientId,
      pkceMethods: const {NativeGatewayPkceMethod.s256},
      capabilities: NativeGatewayCapabilities(known),
    );
  }

  NativeGatewaySession parseSession(Object? json) {
    final root = _V2Object.root(json)
      ..only(const {
        'userId',
        'email',
        'displayName',
        'deviceSessionId',
        'roles',
        'scopes',
        'grants',
        'expiresAt',
      });
    final email = root.string('email');
    if (!_isEmail(email)) {
      throw CoordinatorProtocolException(
        'Expected an email address at ${root.path}.email.',
        path: '${root.path}.email',
      );
    }
    final roles = root
        .uniqueStrings('roles')
        .map(
          (value) => switch (value) {
            'configured_owner' => NativeGatewaySessionRole.configuredOwner,
            'invited_operator' => NativeGatewaySessionRole.invitedOperator,
            _ => throw CoordinatorProtocolException(
              'Unknown session role.',
              path: '${root.path}.roles',
            ),
          },
        )
        .toList(growable: false);
    final scopes = root.uniqueStrings('scopes');
    final grants = root
        .objects('grants')
        .map(_parseGrant)
        .toList(growable: false);

    return NativeGatewaySession(
      userId: root.nonEmptyString('userId'),
      email: email,
      displayName: root.optionalNullableString('displayName'),
      deviceSessionId: root.nonEmptyString('deviceSessionId'),
      roles: roles,
      scopes: scopes,
      grants: grants,
      expiresAt: root.dateTime('expiresAt'),
    );
  }

  NativeGatewayInventory parseInventory(Object? json) {
    final root = _V2Object.root(json)
      ..only(const {
        'revision',
        'observedAt',
        'partial',
        'projects',
        'resources',
        'leases',
        'blockers',
      });
    final projects = root
        .objects('projects')
        .map(_parseProject)
        .toList(growable: false);
    final resources = root
        .objects('resources')
        .map(_parseResource)
        .toList(growable: false);
    final leases = root
        .objects('leases')
        .map(_parseLease)
        .toList(growable: false);
    _uniqueBy(projects, (project) => project.id, '${root.path}.projects');
    _uniqueBy(resources, (resource) => resource.id, '${root.path}.resources');
    _uniqueBy(leases, (lease) => lease.id, '${root.path}.leases');
    final inventory = NativeGatewayInventory(
      revision: root.nonEmptyString('revision'),
      observedAt: root.dateTime('observedAt'),
      partial: root.boolean('partial'),
      projects: projects,
      resources: resources,
      leases: leases,
      blockers: root
          .objects('blockers')
          .map(_parseBlocker)
          .toList(growable: false),
    );
    if (inventory.partial) {
      final frozen = deepFreezeJson(root.value)! as JsonObject;
      throw CoordinatorSemanticException(
        'Native gateway inventory is partial and cannot authorize actions.',
        response: frozen,
      );
    }
    return inventory;
  }

  NativeGatewayEventPage parseEventPage(Object? json) {
    final root = _V2Object.root(json)
      ..only(const {'events', 'nextCursor', 'hasMore'});
    final events = root
        .objects('events')
        .map(_parseEvent)
        .toList(growable: false);
    _uniqueBy(events, (event) => event.id, '${root.path}.events');
    return NativeGatewayEventPage(
      events: events,
      nextCursor: root.nullableString('nextCursor'),
      hasMore: root.boolean('hasMore'),
    );
  }

  NativeGatewayLogPage parseLogPage(Object? json) {
    final root = _V2Object.root(json)
      ..only(const {'lines', 'nextCursor', 'truncated'});
    return NativeGatewayLogPage(
      lines: root.strings('lines'),
      nextCursor: root.nullableString('nextCursor'),
      truncated: root.boolean('truncated'),
    );
  }

  NativeGatewayPortLease parsePortLease(Object? json) =>
      _parseLease(_V2Object.root(json));

  NativeGatewayLifecyclePlan parseLifecyclePlan(Object? json) {
    final root = _V2Object.root(json)
      ..only(const {
        'id',
        'fingerprint',
        'targetId',
        'action',
        'effects',
        'retained',
        'deleted',
        'blockers',
        'confirmationPhrase',
        'expiresAt',
      });
    return NativeGatewayLifecyclePlan(
      id: root.nonEmptyString('id'),
      fingerprint: root.nonEmptyString('fingerprint'),
      targetId: root.nonEmptyString('targetId'),
      action: _lifecycleAction(root.string('action'), '${root.path}.action'),
      effects: root.strings('effects'),
      retained: root.strings('retained'),
      deleted: root.strings('deleted'),
      blockers: root
          .objects('blockers')
          .map(_parseBlocker)
          .toList(growable: false),
      confirmationPhrase: root.string('confirmationPhrase'),
      expiresAt: root.dateTime('expiresAt'),
    );
  }

  NativeGatewayOperation parseOperation(Object? json) {
    final root = _V2Object.root(json)
      ..only(const {
        'id',
        'status',
        'partial',
        'needsAttention',
        'startedAt',
        'finishedAt',
        'resultRevision',
        'results',
        'errors',
      });
    final id = root.nonEmptyString('id');
    try {
      NativeGatewayIdempotencyKey.parse(id);
    } on ArgumentError {
      throw CoordinatorProtocolException(
        'Expected a UUID at ${root.path}.id.',
        path: '${root.path}.id',
      );
    }
    return NativeGatewayOperation(
      id: id.toLowerCase(),
      status: _operationStatus(root.string('status'), '${root.path}.status'),
      partial: root.boolean('partial'),
      needsAttention: root.boolean('needsAttention'),
      startedAt: root.dateTime('startedAt'),
      finishedAt: root.optionalNullableDateTime('finishedAt'),
      resultRevision: root.optionalNullableString('resultRevision'),
      results: root
          .objects('results')
          .map(_parseOperationResult)
          .toList(growable: false),
      errors: root.objects('errors').map(_parseProblem).toList(growable: false),
    );
  }

  NativeGatewayProblem parseProblem(Object? json) =>
      _parseProblem(_V2Object.root(json));

  NativeGatewayGrant _parseGrant(_V2Object value) {
    value.only(const {'resourceId', 'permissions'});
    return NativeGatewayGrant(
      resourceId: value.nonEmptyString('resourceId'),
      permissions: value.uniqueStrings('permissions'),
    );
  }

  NativeGatewayProject _parseProject(_V2Object value) {
    value.only(const {'id', 'displayName', 'state', 'allowedActions'});
    return NativeGatewayProject(
      id: value.nonEmptyString('id'),
      displayName: value.string('displayName'),
      state: _resourceState(value.string('state'), '${value.path}.state'),
      allowedActions: value
          .strings('allowedActions')
          .map(
            (action) => _resourceAction(action, '${value.path}.allowedActions'),
          )
          .toList(growable: false),
    );
  }

  NativeGatewayResource _parseResource(_V2Object value) {
    value.only(const {
      'id',
      'projectId',
      'kind',
      'displayName',
      'state',
      'port',
      'cpuPercent',
      'memoryBytes',
      'allowedActions',
      'blockers',
    });
    return NativeGatewayResource(
      id: value.nonEmptyString('id'),
      projectId: value.nullableString('projectId'),
      kind: _resourceKind(value.string('kind'), '${value.path}.kind'),
      displayName: value.string('displayName'),
      state: _resourceState(value.string('state'), '${value.path}.state'),
      port: value.optionalNullableInteger('port', minimum: 1, maximum: 65535),
      cpuPercent: value.optionalNullableNumber('cpuPercent', minimum: 0),
      memoryBytes: value.optionalNullableInteger('memoryBytes', minimum: 0),
      allowedActions: value
          .strings('allowedActions')
          .map(
            (action) => _resourceAction(action, '${value.path}.allowedActions'),
          )
          .toList(growable: false),
      blockers: value
          .objects('blockers')
          .map(_parseBlocker)
          .toList(growable: false),
    );
  }

  NativeGatewayPortLease _parseLease(_V2Object value) {
    value.only(const {
      'id',
      'projectId',
      'serverResourceId',
      'port',
      'purpose',
      'status',
      'releasable',
      'expiresAt',
      'createdAt',
    });
    final serverResourceId = value.optionalNullableString('serverResourceId');
    if (serverResourceId != null && serverResourceId.trim().isEmpty) {
      throw CoordinatorProtocolException(
        'Expected a non-empty server identity.',
        path: '${value.path}.serverResourceId',
      );
    }
    final status = _portLeaseStatus(
      value.string('status'),
      '${value.path}.status',
    );
    final releasable = value.boolean('releasable');
    if (releasable && status != NativeGatewayPortLeaseStatus.active) {
      throw CoordinatorProtocolException(
        'Only an active lease may be releasable.',
        path: '${value.path}.releasable',
      );
    }
    return NativeGatewayPortLease(
      id: value.nonEmptyString('id'),
      projectId: value.nonEmptyString('projectId'),
      serverResourceId: serverResourceId,
      port: value.integer('port', minimum: 1, maximum: 65535),
      purpose: value.string('purpose'),
      status: status,
      releasable: releasable,
      expiresAt: value.optionalNullableDateTime('expiresAt'),
      createdAt: value.optionalNullableDateTime('createdAt'),
    );
  }

  NativeGatewayBlocker _parseBlocker(_V2Object value) {
    value.only(const {'code', 'message', 'recovery'});
    return NativeGatewayBlocker(
      code: value.nonEmptyString('code'),
      message: value.string('message'),
      recovery: value.optionalNullableString('recovery'),
    );
  }

  NativeGatewayEvent _parseEvent(_V2Object value) {
    value.only(const {
      'id',
      'projectId',
      'resourceId',
      'kind',
      'code',
      'message',
      'occurredAt',
    });
    return NativeGatewayEvent(
      id: value.nonEmptyString('id'),
      projectId: value.optionalNullableString('projectId'),
      resourceId: value.optionalNullableString('resourceId'),
      kind: value.string('kind'),
      code: value.string('code'),
      message: value.string('message'),
      occurredAt: value.dateTime('occurredAt'),
    );
  }

  NativeGatewayOperationTargetResult _parseOperationResult(_V2Object value) {
    value.only(const {
      'targetId',
      'targetKind',
      'status',
      'message',
      'evidenceIds',
    });
    return NativeGatewayOperationTargetResult(
      targetId: value.nonEmptyString('targetId'),
      targetKind: _operationTargetKind(
        value.string('targetKind'),
        '${value.path}.targetKind',
      ),
      status: _operationTargetStatus(
        value.string('status'),
        '${value.path}.status',
      ),
      message: value.string('message'),
      evidenceIds: value.strings('evidenceIds'),
    );
  }

  NativeGatewayProblem _parseProblem(_V2Object value) {
    for (final required in ['type', 'title', 'status']) {
      value.require(required);
    }
    const standard = {
      'type',
      'title',
      'status',
      'detail',
      'instance',
      'code',
      'requestId',
      'blockers',
    };
    final status = value.integer('status', minimum: 400, maximum: 599);
    final extensions = <String, Object?>{};
    for (final entry in value.value.entries) {
      if (!standard.contains(entry.key)) {
        extensions[entry.key] = deepFreezeJson(
          entry.value,
          '${value.path}.${entry.key}',
        );
      }
    }
    return NativeGatewayProblem(
      type: _uriReference(value.string('type'), '${value.path}.type'),
      title: value.string('title'),
      status: status,
      detail: value.optionalString('detail'),
      instance: value.contains('instance')
          ? _uriReference(value.string('instance'), '${value.path}.instance')
          : null,
      code: value.optionalString('code'),
      requestId: value.optionalString('requestId'),
      blockers: value.contains('blockers')
          ? value.objects('blockers').map(_parseBlocker).toList(growable: false)
          : const [],
      extensions: extensions,
    );
  }
}

final class _V2Object {
  _V2Object(this.value, this.path);

  factory _V2Object.root(Object? value) =>
      _V2Object(_object(value, r'$'), r'$');

  final JsonObject value;
  final String path;

  bool contains(String key) => value.containsKey(key);

  void require(String key) {
    if (!value.containsKey(key)) {
      throw CoordinatorProtocolException(
        'Missing required JSON field $path.$key.',
        path: '$path.$key',
      );
    }
  }

  void only(Set<String> allowed) {
    for (final key in value.keys) {
      if (!allowed.contains(key)) {
        throw CoordinatorProtocolException(
          'Unexpected JSON field $path.$key.',
          path: '$path.$key',
        );
      }
    }
  }

  String string(String key) {
    require(key);
    final item = value[key];
    if (item is! String) {
      throw _type(key, 'a string');
    }
    return item;
  }

  String nonEmptyString(String key) {
    final item = string(key);
    if (item.trim().isEmpty) {
      throw _type(key, 'a non-empty string');
    }
    return item;
  }

  String? optionalString(String key) {
    if (!value.containsKey(key)) {
      return null;
    }
    final item = value[key];
    if (item is! String) {
      throw _type(key, 'a string');
    }
    return item;
  }

  String? nullableString(String key) {
    require(key);
    final item = value[key];
    if (item == null) {
      return null;
    }
    if (item is! String) {
      throw _type(key, 'a string or null');
    }
    return item;
  }

  String? optionalNullableString(String key) {
    if (!value.containsKey(key) || value[key] == null) {
      return null;
    }
    final item = value[key];
    if (item is! String) {
      throw _type(key, 'a string or null');
    }
    return item;
  }

  bool boolean(String key) {
    require(key);
    final item = value[key];
    if (item is! bool) {
      throw _type(key, 'a boolean');
    }
    return item;
  }

  int integer(String key, {int? minimum, int? maximum}) {
    require(key);
    final item = value[key];
    if (item is! int ||
        (minimum != null && item < minimum) ||
        (maximum != null && item > maximum)) {
      throw _type(key, 'an integer in the declared range');
    }
    return item;
  }

  int? optionalNullableInteger(String key, {int? minimum, int? maximum}) {
    if (!value.containsKey(key) || value[key] == null) {
      return null;
    }
    final item = value[key];
    if (item is! int ||
        (minimum != null && item < minimum) ||
        (maximum != null && item > maximum)) {
      throw _type(key, 'an integer in the declared range or null');
    }
    return item;
  }

  double? optionalNullableNumber(String key, {double? minimum}) {
    if (!value.containsKey(key) || value[key] == null) {
      return null;
    }
    final item = value[key];
    if (item is! num ||
        !item.toDouble().isFinite ||
        (minimum != null && item < minimum)) {
      throw _type(key, 'a finite number in the declared range or null');
    }
    return item.toDouble();
  }

  List<Object?> list(String key) {
    require(key);
    final item = value[key];
    if (item is! List) {
      throw _type(key, 'an array');
    }
    return item.cast<Object?>();
  }

  List<String> strings(String key) => list(key).indexed
      .map((entry) {
        final (index, item) = entry;
        if (item is! String) {
          throw CoordinatorProtocolException(
            'Expected a string at $path.$key[$index].',
            path: '$path.$key[$index]',
          );
        }
        return item;
      })
      .toList(growable: false);

  Set<String> uniqueStrings(String key) {
    final items = strings(key);
    final result = <String>{};
    for (final item in items) {
      if (!result.add(item)) {
        throw CoordinatorProtocolException(
          'Expected unique values at $path.$key.',
          path: '$path.$key',
        );
      }
    }
    return result;
  }

  List<_V2Object> objects(String key) => list(key).indexed
      .map((entry) {
        final (index, item) = entry;
        final itemPath = '$path.$key[$index]';
        return _V2Object(_object(item, itemPath), itemPath);
      })
      .toList(growable: false);

  DateTime dateTime(String key) => _dateTime(string(key), '$path.$key');

  DateTime? optionalNullableDateTime(String key) {
    if (!value.containsKey(key) || value[key] == null) {
      return null;
    }
    final item = value[key];
    if (item is! String) {
      throw _type(key, 'an RFC 3339 date-time or null');
    }
    return _dateTime(item, '$path.$key');
  }

  CoordinatorProtocolException _type(String key, String expected) =>
      CoordinatorProtocolException(
        'Expected $expected at $path.$key.',
        path: '$path.$key',
      );
}

JsonObject _object(Object? value, String path) {
  if (value is! Map) {
    throw CoordinatorProtocolException(
      'Expected a JSON object at $path.',
      path: path,
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw CoordinatorProtocolException(
        'Expected string object keys at $path.',
        path: path,
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

DateTime _dateTime(String value, String path) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !value.contains('T') ||
      !RegExp(r'(?:Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(value)) {
    throw CoordinatorProtocolException(
      'Expected an RFC 3339 date-time at $path.',
      path: path,
    );
  }
  return parsed;
}

String _uriReference(String value, String path) {
  if (value.contains(RegExp(r'\s')) || Uri.tryParse(value) == null) {
    throw CoordinatorProtocolException(
      'Expected a URI reference at $path.',
      path: path,
    );
  }
  return value;
}

Uri _httpsEndpoint(String value, String path) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.isAbsolute ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw CoordinatorProtocolException(
      'Expected an absolute HTTPS URL without credentials, query, or fragment.',
      path: path,
    );
  }
  return uri;
}

Uri _sameOriginOAuthEndpoint(String value, String path, Uri issuer) {
  final uri = _httpsEndpoint(value, path);
  if (!_sameOrigin(uri, issuer)) {
    throw CoordinatorProtocolException(
      'OAuth endpoint does not match the native gateway issuer origin.',
      path: path,
    );
  }
  return uri;
}

bool _sameOrigin(Uri first, Uri second) =>
    first.scheme == second.scheme &&
    first.host.toLowerCase() == second.host.toLowerCase() &&
    first.port == second.port;

bool _isEmail(String value) =>
    value.length <= 320 &&
    !value.contains(RegExp(r'\s')) &&
    RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value);

NativeGatewayResourceKind _resourceKind(String value, String path) =>
    switch (value) {
      'server' => NativeGatewayResourceKind.server,
      'container' => NativeGatewayResourceKind.container,
      'database' => NativeGatewayResourceKind.database,
      'worktree' => NativeGatewayResourceKind.worktree,
      _ => throw CoordinatorProtocolException(
        'Unknown resource kind.',
        path: path,
      ),
    };

NativeGatewayResourceState _resourceState(String value, String path) =>
    switch (value) {
      'running' => NativeGatewayResourceState.running,
      'stopped' => NativeGatewayResourceState.stopped,
      'starting' => NativeGatewayResourceState.starting,
      'stopping' => NativeGatewayResourceState.stopping,
      'unhealthy' => NativeGatewayResourceState.unhealthy,
      'archived' => NativeGatewayResourceState.archived,
      'unknown' => NativeGatewayResourceState.unknown,
      _ => throw CoordinatorProtocolException(
        'Unknown resource state.',
        path: path,
      ),
    };

NativeGatewayResourceAction _resourceAction(String value, String path) =>
    switch (value) {
      'start' => NativeGatewayResourceAction.start,
      'stop' => NativeGatewayResourceAction.stop,
      'restart' => NativeGatewayResourceAction.restart,
      _ => throw CoordinatorProtocolException(
        'Unknown resource action.',
        path: path,
      ),
    };

NativeGatewayPortLeaseStatus _portLeaseStatus(String value, String path) =>
    switch (value) {
      'active' => NativeGatewayPortLeaseStatus.active,
      'released' => NativeGatewayPortLeaseStatus.released,
      'stale' => NativeGatewayPortLeaseStatus.stale,
      _ => throw CoordinatorProtocolException(
        'Unknown port lease status.',
        path: path,
      ),
    };

NativeGatewayLifecycleAction _lifecycleAction(String value, String path) =>
    switch (value) {
      'archive' => NativeGatewayLifecycleAction.archive,
      'purge' => NativeGatewayLifecycleAction.purge,
      'restore' => NativeGatewayLifecycleAction.restore,
      _ => throw CoordinatorProtocolException(
        'Unknown lifecycle action.',
        path: path,
      ),
    };

NativeGatewayOperationStatus _operationStatus(String value, String path) =>
    switch (value) {
      'queued' => NativeGatewayOperationStatus.queued,
      'running' => NativeGatewayOperationStatus.running,
      'succeeded' => NativeGatewayOperationStatus.succeeded,
      'failed' => NativeGatewayOperationStatus.failed,
      'timed_out' => NativeGatewayOperationStatus.timedOut,
      'cancelled' => NativeGatewayOperationStatus.cancelled,
      'partial' => NativeGatewayOperationStatus.partial,
      'needs_attention' => NativeGatewayOperationStatus.needsAttention,
      _ => throw CoordinatorProtocolException(
        'Unknown operation status.',
        path: path,
      ),
    };

NativeGatewayOperationTargetKind _operationTargetKind(
  String value,
  String path,
) => switch (value) {
  'project' => NativeGatewayOperationTargetKind.project,
  'server' => NativeGatewayOperationTargetKind.server,
  'container' => NativeGatewayOperationTargetKind.container,
  'database' => NativeGatewayOperationTargetKind.database,
  'route' => NativeGatewayOperationTargetKind.route,
  'port_lease' => NativeGatewayOperationTargetKind.portLease,
  'worktree' => NativeGatewayOperationTargetKind.worktree,
  'unassigned_resource' => NativeGatewayOperationTargetKind.unassignedResource,
  _ => throw CoordinatorProtocolException(
    'Unknown operation target kind.',
    path: path,
  ),
};

NativeGatewayOperationTargetStatus _operationTargetStatus(
  String value,
  String path,
) => switch (value) {
  'queued' => NativeGatewayOperationTargetStatus.queued,
  'running' => NativeGatewayOperationTargetStatus.running,
  'succeeded' => NativeGatewayOperationTargetStatus.succeeded,
  'failed' => NativeGatewayOperationTargetStatus.failed,
  'timed_out' => NativeGatewayOperationTargetStatus.timedOut,
  'cancelled' => NativeGatewayOperationTargetStatus.cancelled,
  'blocked' => NativeGatewayOperationTargetStatus.blocked,
  _ => throw CoordinatorProtocolException(
    'Unknown operation target status.',
    path: path,
  ),
};

void _uniqueBy<T>(
  Iterable<T> values,
  String Function(T value) key,
  String path,
) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(key(value))) {
      throw CoordinatorProtocolException(
        'Expected unique identities at $path.',
        path: path,
      );
    }
  }
}
