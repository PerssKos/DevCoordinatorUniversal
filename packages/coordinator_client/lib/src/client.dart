// Public named constructor arguments intentionally omit private field names.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'endpoint.dart';
import 'errors.dart';
import 'inventory_parser.dart';
import 'json_support.dart';
import 'models.dart';

enum _CoordinatorRequestEffect { readOnly, mutation }

abstract interface class CoordinatorTokenProvider {
  Future<String?> readToken();
}

final class CallbackCoordinatorTokenProvider
    implements CoordinatorTokenProvider {
  CallbackCoordinatorTokenProvider(this.callback);

  final Future<String?> Function() callback;

  @override
  Future<String?> readToken() => callback();
}

final class CoordinatorClientLimits {
  const CoordinatorClientLimits({
    this.requestTimeout = const Duration(seconds: 15),
    this.inventoryTimeout = const Duration(seconds: 60),
    this.dockerTimeout = const Duration(seconds: 60),
    this.lifecycleTimeout = const Duration(minutes: 5),
    this.lifecycleApplyTimeout = const Duration(minutes: 10),
    this.maxRequestBytes = 64 * 1024,
    this.maxResponseBytes = 1024 * 1024,
    this.maxInventoryBytes = 16 * 1024 * 1024,
  });

  final Duration requestTimeout;
  final Duration inventoryTimeout;
  final Duration dockerTimeout;
  final Duration lifecycleTimeout;
  final Duration lifecycleApplyTimeout;
  final int maxRequestBytes;
  final int maxResponseBytes;
  final int maxInventoryBytes;

  void validate() {
    for (final timeout in [
      requestTimeout,
      inventoryTimeout,
      dockerTimeout,
      lifecycleTimeout,
      lifecycleApplyTimeout,
    ]) {
      if (timeout <= Duration.zero) {
        throw ArgumentError.value(timeout, 'timeout', 'must be positive');
      }
    }
    if (maxRequestBytes <= 0 ||
        maxResponseBytes <= 0 ||
        maxInventoryBytes <= 0) {
      throw ArgumentError('Body limits must be positive.');
    }
  }
}

/// Transport-neutral contract consumed by application features.
///
/// Native gateway v2 will implement this interface after its server contract
/// is approved. It must never silently fall back to legacy v1 credentials.
abstract interface class CoordinatorGateway {
  CoordinatorEndpoint get endpoint;

  /// Returns capabilities for the selected connection contract.
  ///
  /// Native v2 obtains these from its public metadata endpoint. Legacy v1
  /// first verifies the public service marker, then returns a conservative
  /// static map of the exact methods implemented by that fixed contract.
  Future<CoordinatorMeta> readMeta();

  Future<CoordinatorInventory> readInventory();

  Future<CoordinatorEventPage> readEvents({String? after, int limit = 100});

  Future<CoordinatorActionResult> startServer(
    CoordinatorServerStartRequest request,
  );

  Future<CoordinatorActionResult> actOnServer({
    required CoordinatorServerTarget target,
    required CoordinatorActor actor,
    required CoordinatorResourceAction action,
    String? reason,
  });

  Future<CoordinatorLogResult> readServerLogs(
    CoordinatorServerTarget target, {
    int tail = 200,
  });

  Future<CoordinatorActionResult> actOnProject({
    required CoordinatorProjectTarget target,
    required CoordinatorActor actor,
    required CoordinatorProjectAction action,
  });

  Future<CoordinatorActionResult> actOnContainer({
    required CoordinatorContainerTarget target,
    required CoordinatorActor actor,
    required CoordinatorResourceAction action,
  });

  Future<CoordinatorLogResult> readContainerLogs(
    CoordinatorContainerTarget target, {
    int tail = 120,
  });

  Future<CoordinatorLease> leasePort(CoordinatorPortLeaseRequest request);

  Future<CoordinatorActionResult> releasePort({
    required CoordinatorLeaseTarget target,
    required CoordinatorActor actor,
  });

  Future<CoordinatorActionResult> assignPort({
    required CoordinatorPortAssignmentTarget target,
    required CoordinatorActor actor,
    required int port,
  });

  Future<CoordinatorActionResult> unassignPort({
    required CoordinatorPortAssignmentTarget target,
    required CoordinatorActor actor,
  });

  Future<List<CoordinatorArchive>> readArchives();

  Future<CoordinatorLifecyclePlan> planLifecycle({
    required CoordinatorLifecycleTarget target,
    required CoordinatorLifecyclePlanAction action,
    required CoordinatorActor actor,
    required String reason,
  });

  Future<CoordinatorActionResult> applyLifecycle(
    CoordinatorLifecycleApply apply,
  );

  Future<CoordinatorActionResult> restoreLifecycle({
    required CoordinatorLifecycleTarget target,
    required CoordinatorActor actor,
    required String reason,
  });

  void close();
}

/// Application-facing adapter seam for the future HTTPS gateway.
///
/// The independently testable v2 core transport and DTOs live beside this
/// interface. A future app adapter must explicitly translate those DTOs into
/// the legacy-neutral [CoordinatorGateway] feature model; it must never
/// downgrade to v1 credentials.
abstract interface class NativeGatewayV2Client implements CoordinatorGateway {}

final class LegacyLoopbackV1Client implements CoordinatorGateway {
  LegacyLoopbackV1Client({
    required CoordinatorEndpoint endpoint,
    required CoordinatorTokenProvider tokenProvider,
    required http.Client httpClient,
    CoordinatorClientLimits limits = const CoordinatorClientLimits(),
    CoordinatorInventoryParser parser = const CoordinatorInventoryParser(),
    bool closeHttpClient = false,
  }) : endpoint = endpoint,
       _tokenProvider = tokenProvider,
       _httpClient = httpClient,
       _limits = limits,
       _parser = parser,
       _closeHttpClient = closeHttpClient {
    if (endpoint.kind != CoordinatorConnectionKind.legacyLoopbackV1) {
      throw const CoordinatorEndpointException(
        'LegacyLoopbackV1Client requires a legacy v1 endpoint.',
      );
    }
    limits.validate();
  }

  @override
  final CoordinatorEndpoint endpoint;
  final CoordinatorTokenProvider _tokenProvider;
  final http.Client _httpClient;
  final CoordinatorClientLimits _limits;
  final CoordinatorInventoryParser _parser;
  final bool _closeHttpClient;
  bool _closed = false;

  @override
  Future<CoordinatorMeta> readMeta() async {
    final serverVersion = await _verifyPublicServiceIdentity();
    return CoordinatorMeta(
      apiMajor: 1,
      connectionKind: CoordinatorConnectionKind.legacyLoopbackV1,
      capabilities: CoordinatorCapabilities(
        CoordinatorCapability.values.where(
          (capability) =>
              capability != CoordinatorCapability.containerLifecycle,
        ),
      ),
      serverVersion: serverVersion,
    );
  }

  @override
  Future<CoordinatorInventory> readInventory() async {
    final value = await _requestObject(
      'GET',
      '/v1/inventory',
      timeout: _limits.inventoryTimeout,
      responseLimit: _limits.maxInventoryBytes,
      effect: _CoordinatorRequestEffect.readOnly,
    );
    return _parser.parse(value);
  }

  @override
  Future<CoordinatorEventPage> readEvents({
    String? after,
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    final normalizedAfter = after?.trim();
    if (after != null && (normalizedAfter == null || normalizedAfter.isEmpty)) {
      throw ArgumentError.value(after, 'after', 'must not be empty');
    }
    final value = await _requestObject(
      'GET',
      '/v1/events',
      query: {'limit': '$limit', 'after': ?normalizedAfter},
      semanticCheck: false,
      effect: _CoordinatorRequestEffect.readOnly,
    );
    return _parser.parseEventPage(value);
  }

  @override
  Future<CoordinatorActionResult> startServer(
    CoordinatorServerStartRequest request,
  ) async {
    final body = <String, Object?>{
      'agent': request.actor.value,
      'project': request.target.projectRoot,
      'name': request.target.name,
      'argv': request.arguments,
      'range': request.range.wireValue,
      if (request.cwd != null) 'cwd': request.cwd,
      if (request.preferredPort != null) 'preferred': request.preferredPort,
      if (request.healthUrl != null) 'health_url': request.healthUrl,
      if (request.leaseId != null) 'lease_id': request.leaseId,
    };
    return _action(
      '/v1/servers/start',
      body,
      timeout: _limits.lifecycleTimeout,
    );
  }

  @override
  Future<CoordinatorActionResult> actOnServer({
    required CoordinatorServerTarget target,
    required CoordinatorActor actor,
    required CoordinatorResourceAction action,
    String? reason,
  }) {
    if (action == CoordinatorResourceAction.start) {
      throw ArgumentError(
        'Starting a server requires CoordinatorServerStartRequest.',
      );
    }
    return _action('/v1/servers/${action.name}', {
      'server_id': target.id,
      'agent': actor.value,
      'project': target.projectRoot,
      'name': target.name,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    }, timeout: _limits.lifecycleTimeout);
  }

  @override
  Future<CoordinatorLogResult> readServerLogs(
    CoordinatorServerTarget target, {
    int tail = 200,
  }) async {
    _validateTail(tail);
    final value = await _requestObject(
      'POST',
      '/v1/servers/logs',
      body: {
        'server_id': target.id,
        'project': target.projectRoot,
        'name': target.name,
        'tail': tail,
      },
      effect: _CoordinatorRequestEffect.readOnly,
    );
    return _logResult(value);
  }

  @override
  Future<CoordinatorActionResult> actOnProject({
    required CoordinatorProjectTarget target,
    required CoordinatorActor actor,
    required CoordinatorProjectAction action,
  }) => _action(
    '/v1/projects/${action.name}',
    {
      'project': target.canonicalRoot,
      if (action != CoordinatorProjectAction.status) 'agent': actor.value,
    },
    timeout: _limits.lifecycleTimeout,
    mutating: action != CoordinatorProjectAction.status,
  );

  @override
  Future<CoordinatorActionResult> actOnContainer({
    required CoordinatorContainerTarget target,
    required CoordinatorActor actor,
    required CoordinatorResourceAction action,
  }) async {
    throw const CoordinatorCapabilityException(
      'Legacy v1 cannot prove an exact immutable container mutation target.',
    );
  }

  @override
  Future<CoordinatorLogResult> readContainerLogs(
    CoordinatorContainerTarget target, {
    int tail = 120,
  }) async {
    _validateTail(tail);
    final containerId = target.containerId;
    if (containerId == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(containerId)) {
      throw const CoordinatorCapabilityException(
        'Legacy v1 container logs require an exact immutable Docker container ID.',
      );
    }
    final value = await _requestObject(
      'POST',
      '/v1/docker/logs',
      body: {'container': containerId, 'tail': tail},
      timeout: _limits.dockerTimeout,
      effect: _CoordinatorRequestEffect.readOnly,
    );
    return _logResult(value);
  }

  @override
  Future<CoordinatorLease> leasePort(
    CoordinatorPortLeaseRequest request,
  ) async {
    final value = await _requestObject(
      'POST',
      '/v1/ports/lease',
      body: {
        'agent': request.actor.value,
        'project': request.project.canonicalRoot,
        // Legacy v1 resolves the broker enrollment by the repository-scoped
        // unique server name. The typed request still retains and validates
        // the immutable server definition ID before reaching this wire shape.
        'name': request.server.name,
        'range': request.range.wireValue,
        if (request.preferredPort != null) 'preferred': request.preferredPort,
        if (request.ttl != null) 'ttl': request.ttl!.inSeconds,
        if (request.purpose != null) 'purpose': request.purpose,
      },
      effect: _CoordinatorRequestEffect.mutation,
    );
    return _parser.parseLease(value);
  }

  @override
  Future<CoordinatorActionResult> releasePort({
    required CoordinatorLeaseTarget target,
    required CoordinatorActor actor,
  }) => _action('/v1/ports/release', {
    'agent': actor.value,
    'project': target.projectRoot,
    'lease_id': target.leaseId,
  });

  @override
  Future<CoordinatorActionResult> assignPort({
    required CoordinatorPortAssignmentTarget target,
    required CoordinatorActor actor,
    required int port,
  }) {
    _validatePort(port);
    return _action('/v1/ports/assign', {
      'agent': actor.value,
      'project': target.projectRoot,
      'name': target.serverName,
      'port': port,
    });
  }

  @override
  Future<CoordinatorActionResult> unassignPort({
    required CoordinatorPortAssignmentTarget target,
    required CoordinatorActor actor,
  }) => _action('/v1/ports/unassign', {
    'agent': actor.value,
    'project': target.projectRoot,
    'name': target.serverName,
  });

  @override
  Future<List<CoordinatorArchive>> readArchives() async {
    final value = await _requestObject(
      'GET',
      '/v1/archives',
      timeout: _limits.lifecycleTimeout,
      semanticCheck: false,
      effect: _CoordinatorRequestEffect.readOnly,
    );
    return _parser.parseArchives(value);
  }

  @override
  Future<CoordinatorLifecyclePlan> planLifecycle({
    required CoordinatorLifecycleTarget target,
    required CoordinatorLifecyclePlanAction action,
    required CoordinatorActor actor,
    required String reason,
  }) async {
    final normalizedReason = _requiredReason(reason);
    final value = await _requestObject(
      'POST',
      '/v1/lifecycle/plan',
      body: {
        'target_kind': target.kind.wireValue,
        'target_id': target.id,
        'action': action.name,
        'reason': normalizedReason,
      },
      timeout: _limits.lifecycleTimeout,
      effect: _CoordinatorRequestEffect.mutation,
    );
    return _parser.parseLifecyclePlan(value);
  }

  @override
  Future<CoordinatorActionResult> applyLifecycle(
    CoordinatorLifecycleApply apply,
  ) => _action('/v1/lifecycle/apply', {
    'plan_id': apply.planId,
    'plan_fingerprint': apply.planFingerprint,
    'confirmation_phrase': apply.confirmationPhrase,
  }, timeout: _limits.lifecycleApplyTimeout);

  @override
  Future<CoordinatorActionResult> restoreLifecycle({
    required CoordinatorLifecycleTarget target,
    required CoordinatorActor actor,
    required String reason,
  }) {
    final normalizedReason = _requiredReason(reason);
    return _action('/v1/lifecycle/restore', {
      'target_kind': target.kind.wireValue,
      'target_id': target.id,
      'reason': normalizedReason,
    }, timeout: _limits.lifecycleTimeout);
  }

  Future<CoordinatorActionResult> _action(
    String path,
    Map<String, Object?> body, {
    Duration? timeout,
    bool mutating = true,
  }) async {
    final result = await _requestObject(
      'POST',
      path,
      body: body,
      timeout: timeout,
      effect: mutating
          ? _CoordinatorRequestEffect.mutation
          : _CoordinatorRequestEffect.readOnly,
    );
    _requireAffirmativeActionResult(path, result, requestBody: body);
    return CoordinatorActionResult(
      data: result,
      ok: result['ok'] as bool?,
      status: result['status'] as String?,
    );
  }

  Future<JsonObject> _requestObject(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    Duration? timeout,
    int? responseLimit,
    bool semanticCheck = true,
    required _CoordinatorRequestEffect effect,
  }) async {
    if (_closed) {
      throw const CoordinatorTransportException(
        'Coordinator client is closed.',
      );
    }
    final effectiveTimeout = timeout ?? _limits.requestTimeout;
    var requestStarted = false;
    var deadlineExpired = false;
    try {
      return await _performRequest(
        method,
        path,
        query: query,
        body: body,
        responseLimit: responseLimit ?? _limits.maxResponseBytes,
        semanticCheck: semanticCheck,
        onRequestStarted: () {
          requestStarted = true;
        },
        mayStartRequest: () => !deadlineExpired,
      ).timeout(
        effectiveTimeout,
        onTimeout: () {
          deadlineExpired = true;
          throw TimeoutException('Coordinator request deadline expired.');
        },
      );
    } on TimeoutException {
      if (effect == _CoordinatorRequestEffect.mutation && requestStarted) {
        throw CoordinatorMutationOutcomeUnknownException(
          method: method,
          path: path,
          timeout: effectiveTimeout,
        );
      }
      throw CoordinatorTimeoutException(
        'Coordinator request timed out.',
        timeout: effectiveTimeout,
      );
    } on CoordinatorException {
      rethrow;
    } catch (_) {
      if (effect == _CoordinatorRequestEffect.mutation && requestStarted) {
        throw CoordinatorMutationOutcomeUnknownException(
          method: method,
          path: path,
          timeout: effectiveTimeout,
        );
      }
      throw const CoordinatorTransportException(
        'Coordinator request failed before a valid response was received.',
      );
    }
  }

  Future<JsonObject> _performRequest(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    required int responseLimit,
    required bool semanticCheck,
    required void Function() onRequestStarted,
    required bool Function() mayStartRequest,
  }) async {
    final token = await _readToken();
    final request = http.Request(method, endpoint.resolve(path, query));
    request.followRedirects = false;
    request.headers['accept'] = 'application/json';
    request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      if (bytes.length > _limits.maxRequestBytes) {
        throw CoordinatorBodyTooLargeException(
          'Coordinator request body exceeds the configured limit.',
          limitBytes: _limits.maxRequestBytes,
        );
      }
      request.headers['content-type'] = 'application/json';
      request.bodyBytes = bytes;
    }
    if (!mayStartRequest()) {
      throw TimeoutException(
        'Coordinator request deadline expired before HTTP dispatch.',
      );
    }
    onRequestStarted();
    final streamed = await _httpClient.send(request);
    final bytes = await _readBounded(streamed, responseLimit);
    final contentType = streamed.headers['content-type'];

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final response = _tryDecodeError(bytes, contentType, token);
      final message =
          _safeServerMessage(response) ??
          'Coordinator returned HTTP ${streamed.statusCode}.';
      throw CoordinatorHttpException(
        message,
        statusCode: streamed.statusCode,
        response: response,
      );
    }
    if (bytes.isEmpty) {
      throw CoordinatorProtocolException(
        'Coordinator returned an empty success response.',
        path: path,
      );
    }
    if (!_isJsonContentType(contentType)) {
      throw CoordinatorProtocolException(
        'Coordinator success response is not application/json.',
        path: path,
      );
    }
    final Object? decoded;
    try {
      decoded = redactJsonCredentials(
        jsonDecode(utf8.decode(bytes, allowMalformed: false)),
        token,
      );
    } on FormatException {
      throw CoordinatorProtocolException(
        'Coordinator returned malformed JSON.',
        path: path,
      );
    }
    final object = JsonReader.object(decoded, r'$');
    final frozen = deepFreezeJson(object);
    final result = frozen! as JsonObject;
    if (semanticCheck) {
      _requireSemanticSuccess(result);
    }
    return result;
  }

  Future<String> _verifyPublicServiceIdentity() async {
    if (_closed) {
      throw const CoordinatorTransportException(
        'Coordinator client is closed.',
      );
    }
    try {
      return await _performPublicServiceIdentityRequest().timeout(
        _limits.requestTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Coordinator identity request deadline expired.',
          );
        },
      );
    } on TimeoutException {
      throw CoordinatorTimeoutException(
        'Coordinator identity request timed out.',
        timeout: _limits.requestTimeout,
      );
    } on CoordinatorException {
      rethrow;
    } catch (_) {
      throw const CoordinatorTransportException(
        'Coordinator identity request failed before a valid response was received.',
      );
    }
  }

  Future<String> _performPublicServiceIdentityRequest() async {
    final request = http.Request('GET', endpoint.resolve('/healthz'))
      ..followRedirects = false
      ..headers['accept'] = 'application/json';
    final streamed = await _httpClient.send(request);
    final healthLimit = _limits.maxResponseBytes < 16 * 1024
        ? _limits.maxResponseBytes
        : 16 * 1024;
    final bytes = await _readBounded(streamed, healthLimit);
    if (streamed.statusCode != 200) {
      throw const CoordinatorProtocolException(
        'Selected endpoint did not return the DevCoordinator service marker.',
        path: '/healthz',
      );
    }
    if (!_isJsonContentType(streamed.headers['content-type'])) {
      throw const CoordinatorProtocolException(
        'DevCoordinator service marker is not application/json.',
        path: '/healthz',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      throw const CoordinatorProtocolException(
        'DevCoordinator service marker is malformed.',
        path: '/healthz',
      );
    }
    final object = JsonReader.object(decoded, r'$');
    final exactKeys =
        object.length == 3 &&
        object.containsKey('ok') &&
        object.containsKey('service') &&
        object.containsKey('version');
    final version = object['version'];
    if (!exactKeys ||
        object['ok'] != true ||
        object['service'] != 'codex-dev-coordinator' ||
        version is! String ||
        version.trim().isEmpty) {
      throw const CoordinatorProtocolException(
        'Selected endpoint is not the expected DevCoordinator service.',
        path: '/healthz',
      );
    }
    return version.trim();
  }

  Future<String> _readToken() async {
    final String? supplied;
    try {
      supplied = await _tokenProvider.readToken();
    } catch (_) {
      throw const CoordinatorAuthenticationException(
        'Coordinator credential provider failed.',
      );
    }
    final token = supplied?.trim();
    if (token == null ||
        token.isEmpty ||
        token != supplied ||
        RegExp(r'\s').hasMatch(token)) {
      throw const CoordinatorAuthenticationException(
        'Coordinator credential is unavailable or invalid.',
      );
    }
    return token;
  }

  Future<Uint8List> _readBounded(
    http.StreamedResponse response,
    int limit,
  ) async {
    final declared = response.contentLength;
    if (declared != null && declared > limit) {
      throw CoordinatorBodyTooLargeException(
        'Coordinator response body exceeds the configured limit.',
        limitBytes: limit,
      );
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response.stream) {
      length += chunk.length;
      if (length > limit) {
        throw CoordinatorBodyTooLargeException(
          'Coordinator response body exceeds the configured limit.',
          limitBytes: limit,
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  JsonObject? _tryDecodeError(
    Uint8List bytes,
    String? contentType,
    String token,
  ) {
    if (bytes.isEmpty || !_isJsonContentType(contentType)) {
      return null;
    }
    try {
      final value = redactJsonCredentials(
        jsonDecode(utf8.decode(bytes, allowMalformed: false)),
        token,
      );
      final object = JsonReader.object(value, r'$');
      return deepFreezeJson(object)! as JsonObject;
    } on FormatException {
      return null;
    } on CoordinatorProtocolException {
      return null;
    }
  }

  bool _isJsonContentType(String? value) {
    if (value == null) {
      return false;
    }
    return value.split(';').first.trim().toLowerCase() == 'application/json';
  }

  void _requireSemanticSuccess(JsonObject response) {
    for (final value in _semanticCandidates(response)) {
      final ok = value['ok'];
      if (ok != null && ok is! bool) {
        throw const CoordinatorProtocolException(
          'Semantic field ok must be a boolean.',
          path: r'$.ok',
        );
      }
      final partial = value['partial'];
      final needsAttention = value['needs_attention'];
      final blocked = value['blocked'];
      for (final entry in {
        'partial': partial,
        'needs_attention': needsAttention,
        'blocked': blocked,
      }.entries) {
        if (entry.value != null && entry.value is! bool) {
          throw CoordinatorProtocolException(
            'Semantic field ${entry.key} must be a boolean.',
            path: '\$.${entry.key}',
          );
        }
      }
      final status = value['status'];
      if (status != null && status is! String) {
        throw const CoordinatorProtocolException(
          'Semantic field status must be a string.',
          path: r'$.status',
        );
      }
      final failedStatus =
          status is String &&
          const {
            'blocked',
            'cancelled',
            'degraded',
            'error',
            'failed',
            'partial',
            'needs_attention',
            'incomplete',
            'starting',
            'stopping',
            'timed_out',
            'unhealthy',
            'unknown',
            'wrong_listener',
          }.contains(status.toLowerCase());
      final actionErrors = value['action_errors'];
      if (actionErrors != null && actionErrors is! List) {
        throw const CoordinatorProtocolException(
          'Semantic field action_errors must be an array.',
          path: r'$.action_errors',
        );
      }
      if (ok == false ||
          partial == true ||
          needsAttention == true ||
          blocked == true ||
          failedStatus ||
          (actionErrors is List && actionErrors.isNotEmpty)) {
        throw CoordinatorSemanticException(
          _safeServerMessage(value) ??
              'Coordinator reported an incomplete or failed operation.',
          response: response,
        );
      }
    }
  }

  void _requireAffirmativeActionResult(
    String path,
    JsonObject response, {
    required JsonObject requestBody,
  }) {
    const terminalStatuses = <String>{
      'already_complete',
      'complete',
      'completed',
      'succeeded',
    };
    final endpointStatuses = switch (path) {
      '/v1/servers/start' || '/v1/servers/restart' => const {'running'},
      '/v1/servers/stop' => const {'stopped'},
      '/v1/projects/stop' => const {'stopped'},
      '/v1/ports/release' => const {'released'},
      '/v1/ports/assign' => const {'active'},
      '/v1/ports/unassign' => const {'unassigned'},
      '/v1/lifecycle/restore' => const {'installed', 'restored'},
      _ => const <String>{},
    };
    for (final value in _semanticCandidates(response)) {
      if (value['ok'] == true) {
        return;
      }
      if (path == '/v1/ports/assign' &&
          value['project'] == requestBody['project'] &&
          value['name'] == requestBody['name'] &&
          value['port'] == requestBody['port']) {
        return;
      }
      final status = value['status'];
      if (status is String) {
        final normalized = status.trim().toLowerCase();
        if (terminalStatuses.contains(normalized) ||
            endpointStatuses.contains(normalized)) {
          return;
        }
      }
    }
    throw const CoordinatorProtocolException(
      'Coordinator action response has no affirmative completion evidence.',
      path: r'$',
    );
  }

  List<JsonObject> _semanticCandidates(JsonObject response) {
    final candidates = <JsonObject>[response];
    final nested = response['result'];
    if (nested is Map) {
      candidates.add(JsonReader.object(nested, r'$.result'));
    }
    return candidates;
  }

  String? _safeServerMessage(JsonObject? value) {
    if (value == null) {
      return null;
    }
    for (final key in ['error', 'message', 'classification']) {
      final candidate = value[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  CoordinatorLogResult _logResult(JsonObject value) {
    final text = value['text'];
    final stdout = value['stdout'];
    final stderr = value['stderr'];
    final returnCode = value['returncode'];
    final truncated = value['truncated'] ?? value['output_truncated'];
    if (text != null && text is! String ||
        stdout != null && stdout is! String ||
        stderr != null && stderr is! String ||
        returnCode != null && returnCode is! int ||
        truncated != null && truncated is! bool) {
      throw const CoordinatorProtocolException(
        'Coordinator returned malformed log fields.',
      );
    }
    final explicitText = text as String?;
    final standardOutput = stdout as String?;
    final standardError = stderr as String?;
    return CoordinatorLogResult(
      text: _combinedLogText(explicitText, standardOutput, standardError),
      stdout: standardOutput,
      stderr: standardError,
      exitCode: returnCode as int?,
      truncated: (truncated as bool?) ?? false,
    );
  }

  String _combinedLogText(String? text, String? stdout, String? stderr) {
    final hasStreamOutput =
        (stdout?.isNotEmpty ?? false) || (stderr?.isNotEmpty ?? false);
    if (text != null && (text.isNotEmpty || !hasStreamOutput)) {
      return text;
    }
    if (stdout == null || stdout.isEmpty) {
      return stderr ?? '';
    }
    if (stderr == null || stderr.isEmpty) {
      return stdout;
    }
    final separator = stdout.endsWith('\n') ? '' : '\n';
    return '[stdout]\n$stdout$separator[stderr]\n$stderr';
  }

  void _validateTail(int tail) {
    if (tail < 1 || tail > 10000) {
      throw ArgumentError.value(tail, 'tail', 'must be between 1 and 10000');
    }
  }

  void _validatePort(int port) {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be between 1 and 65535');
    }
  }

  String _requiredReason(String reason) {
    final normalized = reason.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'must not be empty');
    }
    return normalized;
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_closeHttpClient) {
      _httpClient.close();
    }
  }
}
