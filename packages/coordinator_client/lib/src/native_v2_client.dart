// Public named constructor arguments intentionally omit private field names.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'endpoint.dart';
import 'errors.dart';
import 'json_support.dart';
import 'native_v2_models.dart';
import 'native_v2_parser.dart';

abstract interface class NativeGatewayAccessTokenProvider {
  Future<String?> readAccessToken();
}

final class CallbackNativeGatewayAccessTokenProvider
    implements NativeGatewayAccessTokenProvider {
  CallbackNativeGatewayAccessTokenProvider(this.callback);

  final Future<String?> Function() callback;

  @override
  Future<String?> readAccessToken() => callback();
}

final class NativeGatewayV2Limits {
  const NativeGatewayV2Limits({
    this.requestTimeout = const Duration(seconds: 15),
    this.inventoryTimeout = const Duration(seconds: 60),
    this.logTimeout = const Duration(seconds: 30),
    this.maxRequestBytes = 64 * 1024,
    this.maxResponseBytes = 2 * 1024 * 1024,
    this.maxInventoryBytes = 16 * 1024 * 1024,
    this.maxLogBytes = 4 * 1024 * 1024,
    this.maxAccessTokenBytes = 8 * 1024,
  });

  final Duration requestTimeout;
  final Duration inventoryTimeout;
  final Duration logTimeout;
  final int maxRequestBytes;
  final int maxResponseBytes;
  final int maxInventoryBytes;
  final int maxLogBytes;
  final int maxAccessTokenBytes;

  void validate() {
    for (final timeout in [requestTimeout, inventoryTimeout, logTimeout]) {
      if (timeout <= Duration.zero) {
        throw ArgumentError.value(timeout, 'timeout', 'must be positive');
      }
    }
    for (final limit in [
      maxRequestBytes,
      maxResponseBytes,
      maxInventoryBytes,
      maxLogBytes,
      maxAccessTokenBytes,
    ]) {
      if (limit <= 0) {
        throw ArgumentError.value(limit, 'limit', 'must be positive');
      }
    }
  }
}

/// Independently testable transport for the required, non-deferred v2 core.
///
/// This surface intentionally exposes only contract-defined operations. It
/// does not perform OAuth, retain refresh credentials, implement application
/// adapters, or provide arbitrary path/JSON escape hatches.
abstract interface class NativeGatewayV2CoreApi {
  CoordinatorEndpoint get endpoint;

  Future<NativeGatewayDocument<NativeGatewayMeta>> readMeta();

  Future<NativeGatewaySession> readSession();

  Future<void> revokeCurrentSession();

  Future<NativeGatewayConditionalResult<NativeGatewayInventory>> readInventory({
    NativeGatewayEntityTag? ifNoneMatch,
  });

  Future<NativeGatewayEventPage> readEvents({String? after, int limit = 100});

  Future<NativeGatewayOperation> actOnResource({
    required String resourceId,
    required NativeGatewayResourceAction action,
    required NativeGatewayActionRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  });

  Future<NativeGatewayLogPage> readResourceLogs({
    required String resourceId,
    String? cursor,
    int limit = 200,
  });

  Future<NativeGatewayPortLease> createPortLease({
    required NativeGatewayLeaseRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  });

  Future<void> releasePortLease({
    required String leaseId,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  });

  Future<NativeGatewayLifecyclePlan> createLifecyclePlan({
    required NativeGatewayLifecyclePlanRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  });

  Future<NativeGatewayOperation> applyLifecyclePlan({
    required String planId,
    required NativeGatewayLifecycleApplyRequest request,
    required NativeGatewayIdempotencyKey idempotencyKey,
  });

  Future<NativeGatewayOperation> readOperation(String operationId);

  void close();
}

final class NativeGatewayV2CoreClient implements NativeGatewayV2CoreApi {
  NativeGatewayV2CoreClient({
    required CoordinatorEndpoint endpoint,
    required NativeGatewayAccessTokenProvider accessTokenProvider,
    required http.Client httpClient,
    NativeGatewayV2Limits limits = const NativeGatewayV2Limits(),
    NativeGatewayV2Parser parser = const NativeGatewayV2Parser(),
    bool closeHttpClient = false,
  }) : endpoint = endpoint,
       _accessTokenProvider = accessTokenProvider,
       _httpClient = httpClient,
       _limits = limits,
       _parser = parser,
       _closeHttpClient = closeHttpClient {
    if (endpoint.kind != CoordinatorConnectionKind.nativeGatewayV2) {
      throw const CoordinatorEndpointException(
        'NativeGatewayV2CoreClient requires a native v2 endpoint.',
      );
    }
    limits.validate();
  }

  @override
  final CoordinatorEndpoint endpoint;
  final NativeGatewayAccessTokenProvider _accessTokenProvider;
  final http.Client _httpClient;
  final NativeGatewayV2Limits _limits;
  final NativeGatewayV2Parser _parser;
  final bool _closeHttpClient;
  bool _closed = false;

  @override
  Future<NativeGatewayDocument<NativeGatewayMeta>> readMeta() async {
    final response = await _request(
      method: 'GET',
      path: '/meta',
      authenticated: false,
      expectedStatuses: const {200},
      effect: _NativeRequestEffect.readOnly,
    );
    return NativeGatewayDocument(
      value: _parser.parseMeta(response.json),
      entityTag: _optionalEntityTag(response),
    );
  }

  @override
  Future<NativeGatewaySession> readSession() async {
    final response = await _request(
      method: 'GET',
      path: '/session',
      expectedStatuses: const {200},
      effect: _NativeRequestEffect.readOnly,
    );
    return _parser.parseSession(response.json);
  }

  @override
  Future<void> revokeCurrentSession() async {
    await _request(
      method: 'DELETE',
      path: '/session',
      expectedStatuses: const {204},
      effect: _NativeRequestEffect.mutation,
    );
  }

  @override
  Future<NativeGatewayConditionalResult<NativeGatewayInventory>> readInventory({
    NativeGatewayEntityTag? ifNoneMatch,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/inventory',
      headers: {if (ifNoneMatch != null) 'if-none-match': ifNoneMatch.value},
      expectedStatuses: ifNoneMatch == null ? const {200} : const {200, 304},
      timeout: _limits.inventoryTimeout,
      responseLimit: _limits.maxInventoryBytes,
      effect: _NativeRequestEffect.readOnly,
    );
    if (response.statusCode == 304) {
      return NativeGatewayNotModified(entityTag: ifNoneMatch!);
    }
    final entityTag = _requiredEntityTag(response, '/inventory');
    return NativeGatewayModified(
      value: _parser.parseInventory(response.json),
      entityTag: entityTag,
    );
  }

  @override
  Future<NativeGatewayEventPage> readEvents({
    String? after,
    int limit = 100,
  }) async {
    final normalizedAfter = _optionalCursor(after, 'after');
    _range(limit, 'limit', 1, 500);
    final response = await _request(
      method: 'GET',
      path: '/events',
      query: {'limit': '$limit', 'after': ?normalizedAfter},
      expectedStatuses: const {200},
      effect: _NativeRequestEffect.readOnly,
    );
    return _parser.parseEventPage(response.json);
  }

  @override
  Future<NativeGatewayOperation> actOnResource({
    required String resourceId,
    required NativeGatewayResourceAction action,
    required NativeGatewayActionRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) async {
    final target = _opaqueId(resourceId, 'resourceId');
    final response = await _request(
      method: 'POST',
      path: '/resources/{resourceId}/actions/${action.name}',
      pathSegments: ['resources', target, 'actions', action.name],
      headers: _mutationHeaders(ifMatch, idempotencyKey),
      body: request.toJson(),
      expectedStatuses: const {202},
      effect: _NativeRequestEffect.mutation,
    );
    return _parseMutationResponse(
      method: 'POST',
      path: '/resources/{resourceId}/actions/${action.name}',
      json: response.json,
      parse: _parser.parseOperation,
    );
  }

  @override
  Future<NativeGatewayLogPage> readResourceLogs({
    required String resourceId,
    String? cursor,
    int limit = 200,
  }) async {
    final target = _opaqueId(resourceId, 'resourceId');
    final normalizedCursor = _optionalCursor(cursor, 'cursor');
    _range(limit, 'limit', 1, 1000);
    final response = await _request(
      method: 'GET',
      path: '/resources/{resourceId}/logs',
      pathSegments: ['resources', target, 'logs'],
      query: {'limit': '$limit', 'cursor': ?normalizedCursor},
      expectedStatuses: const {200},
      timeout: _limits.logTimeout,
      responseLimit: _limits.maxLogBytes,
      effect: _NativeRequestEffect.readOnly,
    );
    return _parser.parseLogPage(response.json);
  }

  @override
  Future<NativeGatewayPortLease> createPortLease({
    required NativeGatewayLeaseRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/ports/leases',
      headers: _mutationHeaders(ifMatch, idempotencyKey),
      body: request.toJson(),
      expectedStatuses: const {201},
      effect: _NativeRequestEffect.mutation,
    );
    return _parseMutationResponse(
      method: 'POST',
      path: '/ports/leases',
      json: response.json,
      parse: _parser.parsePortLease,
    );
  }

  @override
  Future<void> releasePortLease({
    required String leaseId,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) async {
    final target = _opaqueId(leaseId, 'leaseId');
    await _request(
      method: 'DELETE',
      path: '/ports/leases/{leaseId}',
      pathSegments: ['ports', 'leases', target],
      headers: _mutationHeaders(ifMatch, idempotencyKey),
      expectedStatuses: const {204},
      effect: _NativeRequestEffect.mutation,
    );
  }

  @override
  Future<NativeGatewayLifecyclePlan> createLifecyclePlan({
    required NativeGatewayLifecyclePlanRequest request,
    required NativeGatewayEntityTag ifMatch,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) async {
    final response = await _request(
      method: 'POST',
      path: '/lifecycle/plans',
      headers: _mutationHeaders(ifMatch, idempotencyKey),
      body: request.toJson(),
      expectedStatuses: const {201},
      effect: _NativeRequestEffect.mutation,
    );
    return _parseMutationResponse(
      method: 'POST',
      path: '/lifecycle/plans',
      json: response.json,
      parse: _parser.parseLifecyclePlan,
    );
  }

  @override
  Future<NativeGatewayOperation> applyLifecyclePlan({
    required String planId,
    required NativeGatewayLifecycleApplyRequest request,
    required NativeGatewayIdempotencyKey idempotencyKey,
  }) async {
    final target = _opaqueId(planId, 'planId');
    final response = await _request(
      method: 'POST',
      path: '/lifecycle/plans/{planId}/apply',
      pathSegments: ['lifecycle', 'plans', target, 'apply'],
      headers: {'idempotency-key': idempotencyKey.value},
      body: request.toJson(),
      expectedStatuses: const {202},
      effect: _NativeRequestEffect.mutation,
    );
    return _parseMutationResponse(
      method: 'POST',
      path: '/lifecycle/plans/{planId}/apply',
      json: response.json,
      parse: _parser.parseOperation,
    );
  }

  @override
  Future<NativeGatewayOperation> readOperation(String operationId) async {
    final target = _uuid(operationId, 'operationId');
    final response = await _request(
      method: 'GET',
      path: '/operations/{operationId}',
      pathSegments: ['operations', target],
      expectedStatuses: const {200},
      effect: _NativeRequestEffect.readOnly,
    );
    return _parser.parseOperation(response.json);
  }

  Map<String, String> _mutationHeaders(
    NativeGatewayEntityTag ifMatch,
    NativeGatewayIdempotencyKey idempotencyKey,
  ) => {'if-match': ifMatch.value, 'idempotency-key': idempotencyKey.value};

  Future<_NativeWireResponse> _request({
    required String method,
    required String path,
    required Set<int> expectedStatuses,
    required _NativeRequestEffect effect,
    bool authenticated = true,
    Map<String, String>? query,
    List<String>? pathSegments,
    Map<String, String> headers = const {},
    Map<String, Object?>? body,
    Duration? timeout,
    int? responseLimit,
  }) async {
    if (_closed) {
      throw const CoordinatorTransportException(
        'Native gateway client is closed.',
      );
    }
    final effectiveTimeout = timeout ?? _limits.requestTimeout;
    var requestStarted = false;
    var deadlineExpired = false;
    int? responseStatus;
    try {
      return await _performRequest(
        method: method,
        path: path,
        authenticated: authenticated,
        query: query,
        pathSegments: pathSegments,
        headers: headers,
        body: body,
        expectedStatuses: expectedStatuses,
        responseLimit: responseLimit ?? _limits.maxResponseBytes,
        onRequestStarted: () {
          requestStarted = true;
        },
        onResponseReceived: (statusCode) {
          responseStatus = statusCode;
        },
        mayStartRequest: () => !deadlineExpired,
      ).timeout(
        effectiveTimeout,
        onTimeout: () {
          deadlineExpired = true;
          throw TimeoutException('Native gateway request deadline expired.');
        },
      );
    } on TimeoutException {
      if (effect == _NativeRequestEffect.mutation && requestStarted) {
        throw CoordinatorMutationOutcomeUnknownException(
          method: method,
          path: path,
          timeout: effectiveTimeout,
        );
      }
      throw CoordinatorTimeoutException(
        'Native gateway request timed out.',
        timeout: effectiveTimeout,
      );
    } on CoordinatorException catch (error) {
      final status = responseStatus;
      if (effect == _NativeRequestEffect.mutation &&
          requestStarted &&
          status != null &&
          status >= 200 &&
          status < 300 &&
          (error is CoordinatorProtocolException ||
              error is CoordinatorBodyTooLargeException)) {
        throw CoordinatorMutationOutcomeUnknownException(
          method: method,
          path: path,
          timeout: effectiveTimeout,
        );
      }
      rethrow;
    } catch (_) {
      if (effect == _NativeRequestEffect.mutation && requestStarted) {
        throw CoordinatorMutationOutcomeUnknownException(
          method: method,
          path: path,
          timeout: effectiveTimeout,
        );
      }
      throw const CoordinatorTransportException(
        'Native gateway request failed before a valid response was received.',
      );
    }
  }

  Future<_NativeWireResponse> _performRequest({
    required String method,
    required String path,
    required bool authenticated,
    required Map<String, String>? query,
    required List<String>? pathSegments,
    required Map<String, String> headers,
    required Map<String, Object?>? body,
    required Set<int> expectedStatuses,
    required int responseLimit,
    required void Function() onRequestStarted,
    required void Function(int statusCode) onResponseReceived,
    required bool Function() mayStartRequest,
  }) async {
    final token = authenticated ? await _readAccessToken() : null;
    final uri = pathSegments == null
        ? endpoint.resolve(path, query)
        : endpoint.uri.replace(
            pathSegments: [
              ...endpoint.uri.pathSegments.where(
                (segment) => segment.isNotEmpty,
              ),
              ...pathSegments,
            ],
            queryParameters: (query?.isEmpty ?? true) ? null : query,
          );
    final request = http.Request(method, uri);
    request.followRedirects = false;
    request.maxRedirects = 0;
    request.headers['accept'] = 'application/json, application/problem+json';
    if (token != null) {
      request.headers['authorization'] = 'Bearer $token';
    }
    request.headers.addAll(headers);
    if (body != null) {
      final bodyBytes = utf8.encode(jsonEncode(body));
      if (bodyBytes.length > _limits.maxRequestBytes) {
        throw CoordinatorBodyTooLargeException(
          'Native gateway request body exceeds the configured limit.',
          limitBytes: _limits.maxRequestBytes,
        );
      }
      request.headers['content-type'] = 'application/json';
      request.bodyBytes = bodyBytes;
    }
    if (!mayStartRequest()) {
      throw TimeoutException(
        'Native gateway request deadline expired before HTTP dispatch.',
      );
    }
    onRequestStarted();
    final streamed = await _httpClient.send(request);
    onResponseReceived(streamed.statusCode);
    final bytes = await _readBounded(streamed, responseLimit);
    final status = streamed.statusCode;

    if (!expectedStatuses.contains(status)) {
      if (status < 200 || status >= 300) {
        throw _httpFailure(streamed, bytes, token);
      }
      throw CoordinatorProtocolException(
        'Native gateway returned unexpected HTTP $status.',
        path: path,
      );
    }
    if (status == 204 || status == 304) {
      if (bytes.isNotEmpty) {
        throw CoordinatorProtocolException(
          'Native gateway returned a body for HTTP $status.',
          path: path,
        );
      }
      return _NativeWireResponse(
        statusCode: status,
        headers: Map.unmodifiable(streamed.headers),
      );
    }
    if (bytes.isEmpty) {
      throw CoordinatorProtocolException(
        'Native gateway returned an empty success response.',
        path: path,
      );
    }
    if (!_isContentType(streamed.headers['content-type'], 'application/json')) {
      throw CoordinatorProtocolException(
        'Native gateway success response is not application/json.',
        path: path,
      );
    }
    return _NativeWireResponse(
      statusCode: status,
      headers: Map.unmodifiable(streamed.headers),
      json: _decodeAndRedact(bytes, token, path),
    );
  }

  T _parseMutationResponse<T>({
    required String method,
    required String path,
    required Object? json,
    required T Function(Object? json) parse,
    Duration? timeout,
  }) {
    try {
      return parse(json);
    } on CoordinatorProtocolException {
      throw CoordinatorMutationOutcomeUnknownException(
        method: method,
        path: path,
        timeout: timeout ?? _limits.requestTimeout,
      );
    }
  }

  NativeGatewayProblemException _httpFailure(
    http.StreamedResponse response,
    Uint8List bytes,
    String? token,
  ) {
    if (bytes.isEmpty ||
        !_isContentType(
          response.headers['content-type'],
          'application/problem+json',
        )) {
      throw CoordinatorHttpException(
        'Native gateway returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    final problem = _parser.parseProblem(
      _decodeAndRedact(bytes, token, r'$.problem'),
    );
    return NativeGatewayProblemException(
      httpStatus: response.statusCode,
      problem: problem,
    );
  }

  Object? _decodeAndRedact(Uint8List bytes, String? token, String path) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      throw CoordinatorProtocolException(
        'Native gateway returned malformed JSON.',
        path: path,
      );
    }
    return redactJsonCredentials(decoded, token ?? '\u0000');
  }

  Future<String> _readAccessToken() async {
    final String? supplied;
    try {
      supplied = await _accessTokenProvider.readAccessToken();
    } catch (_) {
      throw const CoordinatorAuthenticationException(
        'Native gateway access-token provider failed.',
      );
    }
    final token = supplied?.trim();
    if (token == null ||
        token.isEmpty ||
        token != supplied ||
        utf8.encode(token).length > _limits.maxAccessTokenBytes ||
        RegExp(r'\s').hasMatch(token)) {
      throw const CoordinatorAuthenticationException(
        'Native gateway access token is unavailable or invalid.',
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
        'Native gateway response body exceeds the configured limit.',
        limitBytes: limit,
      );
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response.stream) {
      length += chunk.length;
      if (length > limit) {
        throw CoordinatorBodyTooLargeException(
          'Native gateway response body exceeds the configured limit.',
          limitBytes: limit,
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  NativeGatewayEntityTag? _optionalEntityTag(_NativeWireResponse response) {
    final raw = response.headers['etag'];
    if (raw == null) {
      return null;
    }
    try {
      return NativeGatewayEntityTag.parse(raw);
    } on ArgumentError {
      throw const CoordinatorProtocolException(
        'Native gateway returned an invalid or weak ETag.',
        path: r'$.headers.etag',
      );
    }
  }

  NativeGatewayEntityTag _requiredEntityTag(
    _NativeWireResponse response,
    String path,
  ) {
    final result = _optionalEntityTag(response);
    if (result == null) {
      throw CoordinatorProtocolException(
        'Native gateway response is missing its strong ETag.',
        path: path,
      );
    }
    return result;
  }

  bool _isContentType(String? value, String expected) =>
      value?.split(';').first.trim().toLowerCase() == expected;

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

enum _NativeRequestEffect { readOnly, mutation }

final class _NativeWireResponse {
  const _NativeWireResponse({
    required this.statusCode,
    required this.headers,
    this.json,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Object? json;
}

String _opaqueId(String value, String name) {
  if (value.trim().isEmpty ||
      value.length > 256 ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw ArgumentError(
      'must be a non-empty opaque identifier of at most 256 characters',
      name,
    );
  }
  return value;
}

String _uuid(String value, String name) {
  try {
    return NativeGatewayIdempotencyKey.parse(value).value;
  } on ArgumentError {
    throw ArgumentError('must be a canonical UUID', name);
  }
}

String? _optionalCursor(String? value, String name) {
  if (value == null) {
    return null;
  }
  if (value.isEmpty ||
      value.length > 1024 ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw ArgumentError('must contain 1 to 1024 characters', name);
  }
  return value;
}

void _range(int value, String name, int minimum, int maximum) {
  if (value < minimum || value > maximum) {
    throw ArgumentError.value(
      value,
      name,
      'must be between $minimum and $maximum',
    );
  }
}
