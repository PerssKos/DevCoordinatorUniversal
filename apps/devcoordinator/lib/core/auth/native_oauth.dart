import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const nativeOAuthClientId = 'io.github.holyglory.devcoordinator';
final Uri nativeOAuthRedirectUri = Uri.parse(
  'io.github.holyglory.devcoordinator://oauth/callback',
);

final class NativeOAuthException implements Exception {
  const NativeOAuthException(
    this.message, {
    this.authenticationRequired = false,
  });

  final String message;
  final bool authenticationRequired;

  @override
  String toString() => message;
}

final class NativeOAuthConfiguration {
  NativeOAuthConfiguration({
    required this.gatewayEndpoint,
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.revocationEndpoint,
    required this.clientId,
    required Iterable<String> pkceMethods,
  }) : pkceMethods = Set.unmodifiable(pkceMethods) {
    _validate();
  }

  final Uri gatewayEndpoint;
  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri revocationEndpoint;
  final String clientId;
  final Set<String> pkceMethods;

  String get bindingKey => [
    _normalizedEndpoint(gatewayEndpoint),
    issuer.toString(),
    clientId,
  ].join('\n');

  void _validate() {
    _validateHttpsUri(gatewayEndpoint, 'gateway endpoint');
    _validateHttpsUri(issuer, 'OAuth issuer');
    _validateHttpsUri(authorizationEndpoint, 'authorization endpoint');
    _validateHttpsUri(tokenEndpoint, 'token endpoint');
    _validateHttpsUri(revocationEndpoint, 'revocation endpoint');
    final gatewayOrigin = _origin(gatewayEndpoint);
    for (final entry in <MapEntry<String, Uri>>[
      MapEntry('OAuth issuer', issuer),
      MapEntry('authorization endpoint', authorizationEndpoint),
      MapEntry('token endpoint', tokenEndpoint),
      MapEntry('revocation endpoint', revocationEndpoint),
    ]) {
      if (_origin(entry.value) != gatewayOrigin) {
        throw NativeOAuthException(
          '${entry.key} must use the selected gateway origin.',
        );
      }
    }
    if (clientId != nativeOAuthClientId) {
      throw const NativeOAuthException(
        'The gateway does not advertise the expected public client ID.',
      );
    }
    if (!pkceMethods.contains('S256')) {
      throw const NativeOAuthException(
        'The gateway does not advertise PKCE S256.',
      );
    }
  }

  static void _validateHttpsUri(Uri value, String label) {
    if (value.scheme != 'https' ||
        value.host.isEmpty ||
        value.hasFragment ||
        value.userInfo.isNotEmpty) {
      throw NativeOAuthException(
        '$label must be an HTTPS URL without credentials or a fragment.',
      );
    }
  }

  static String _origin(Uri value) {
    final port = value.hasPort ? value.port : 443;
    return '${value.scheme.toLowerCase()}://${value.host.toLowerCase()}:$port';
  }

  static String _normalizedEndpoint(Uri value) => value
      .replace(
        scheme: value.scheme.toLowerCase(),
        host: value.host.toLowerCase(),
        fragment: '',
      )
      .toString();
}

final class NativePkceTransaction {
  const NativePkceTransaction({
    required this.state,
    required this.verifier,
    required this.challenge,
    required this.createdAt,
  });

  factory NativePkceTransaction.generate({
    Random? random,
    DateTime Function()? clock,
  }) {
    final source = random ?? Random.secure();
    final state = _randomBase64Url(source, 32);
    final verifier = _randomBase64Url(source, 64);
    final challenge = nativePkceS256Challenge(verifier);
    return NativePkceTransaction(
      state: state,
      verifier: verifier,
      challenge: challenge,
      createdAt: (clock ?? DateTime.now)().toUtc(),
    );
  }

  final String state;
  final String verifier;
  final String challenge;
  final DateTime createdAt;

  static String _randomBase64Url(Random source, int byteCount) {
    final bytes = Uint8List.fromList(
      List<int>.generate(byteCount, (_) => source.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

final class NativeOAuthTokenSet {
  NativeOAuthTokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required Iterable<String> scopes,
    this.deviceSessionId,
  }) : scopes = Set.unmodifiable(scopes);

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final Set<String> scopes;
  final String? deviceSessionId;
}

final class NativeOAuthClient {
  NativeOAuthClient(
    this._httpClient, {
    this.requestTimeout = const Duration(seconds: 20),
    this.maxResponseBytes = 64 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final http.Client _httpClient;
  final Duration requestTimeout;
  final int maxResponseBytes;
  final DateTime Function() _clock;

  Uri authorizationUri({
    required NativeOAuthConfiguration configuration,
    required NativePkceTransaction transaction,
    required Iterable<String> scopes,
  }) {
    final normalizedScopes =
        scopes
            .map((scope) => scope.trim())
            .where((scope) => scope.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (normalizedScopes.isEmpty) {
      throw const NativeOAuthException('At least one OAuth scope is required.');
    }
    return configuration.authorizationEndpoint.replace(
      queryParameters: <String, String>{
        ...configuration.authorizationEndpoint.queryParameters,
        'response_type': 'code',
        'client_id': configuration.clientId,
        'redirect_uri': nativeOAuthRedirectUri.toString(),
        'scope': normalizedScopes.join(' '),
        'state': transaction.state,
        'code_challenge': transaction.challenge,
        'code_challenge_method': 'S256',
      },
    );
  }

  Future<NativeOAuthTokenSet> exchangeAuthorizationCode({
    required NativeOAuthConfiguration configuration,
    required String code,
    required String verifier,
  }) {
    return _tokenRequest(configuration, <String, String>{
      'grant_type': 'authorization_code',
      'client_id': configuration.clientId,
      'code': _requiredOpaque(code, 'authorization code'),
      'redirect_uri': nativeOAuthRedirectUri.toString(),
      'code_verifier': _requiredVerifier(verifier),
    });
  }

  Future<NativeOAuthTokenSet> refresh({
    required NativeOAuthConfiguration configuration,
    required String refreshToken,
  }) {
    return _tokenRequest(configuration, <String, String>{
      'grant_type': 'refresh_token',
      'client_id': configuration.clientId,
      'refresh_token': _requiredToken(refreshToken, 'refresh token'),
    });
  }

  Future<void> revoke({
    required NativeOAuthConfiguration configuration,
    required String refreshToken,
  }) async {
    final response =
        await _sendForm(configuration.revocationEndpoint, <String, String>{
          'client_id': configuration.clientId,
          'token': _requiredToken(refreshToken, 'refresh token'),
          'token_type_hint': 'refresh_token',
        });
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw NativeOAuthException(
        'OAuth revocation failed with HTTP ${response.statusCode}.',
        authenticationRequired:
            response.statusCode == 400 || response.statusCode == 401,
      );
    }
  }

  Future<NativeOAuthTokenSet> _tokenRequest(
    NativeOAuthConfiguration configuration,
    Map<String, String> body,
  ) async {
    final response = await _sendForm(configuration.tokenEndpoint, body);
    if (response.statusCode != 200) {
      final code = _safeOAuthError(response);
      throw NativeOAuthException(
        code == null
            ? 'OAuth token exchange failed with HTTP ${response.statusCode}.'
            : 'OAuth token exchange failed: $code.',
        authenticationRequired:
            code == 'invalid_grant' ||
            code == 'invalid_token' ||
            code == 'access_denied' ||
            response.statusCode == 401,
      );
    }
    final contentType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (contentType != 'application/json') {
      throw const NativeOAuthException(
        'OAuth token response is not application/json.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const NativeOAuthException('OAuth token response is malformed.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const NativeOAuthException('OAuth token response is malformed.');
    }
    final tokenType = decoded['token_type'];
    final accessToken = decoded['access_token'];
    final refreshToken = decoded['refresh_token'];
    final expiresIn = decoded['expires_in'];
    final scope = decoded['scope'];
    final deviceSessionId = decoded['device_session_id'];
    if (tokenType is! String ||
        tokenType.toLowerCase() != 'bearer' ||
        accessToken is! String ||
        refreshToken is! String ||
        expiresIn is! int ||
        expiresIn < 1 ||
        expiresIn > 86400 ||
        (scope != null && scope is! String) ||
        (deviceSessionId != null && deviceSessionId is! String)) {
      throw const NativeOAuthException(
        'OAuth token response is missing required fields.',
      );
    }
    return NativeOAuthTokenSet(
      accessToken: _requiredToken(accessToken, 'access token'),
      refreshToken: _requiredToken(refreshToken, 'rotating refresh token'),
      expiresAt: _clock().toUtc().add(Duration(seconds: expiresIn)),
      scopes: scope == null || scope.trim().isEmpty
          ? const <String>{}
          : scope.split(RegExp(r'\s+')).toSet(),
      deviceSessionId: deviceSessionId == null
          ? null
          : _requiredOpaque(deviceSessionId, 'device session ID'),
    );
  }

  Future<http.Response> _sendForm(Uri uri, Map<String, String> fields) async {
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['accept'] = 'application/json'
      ..headers['content-type'] = 'application/x-www-form-urlencoded'
      ..bodyFields = fields;
    final http.StreamedResponse streamed;
    try {
      streamed = await _httpClient.send(request).timeout(requestTimeout);
    } on TimeoutException {
      throw const NativeOAuthException('OAuth request timed out.');
    } catch (_) {
      throw const NativeOAuthException(
        'OAuth server could not be reached securely.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in streamed.stream) {
      length += chunk.length;
      if (length > maxResponseBytes) {
        throw const NativeOAuthException('OAuth response is too large.');
      }
      bytes.add(chunk);
    }
    return http.Response.bytes(
      bytes.takeBytes(),
      streamed.statusCode,
      headers: streamed.headers,
      request: request,
    );
  }

  static String? _safeOAuthError(http.Response response) {
    if (response.bodyBytes.isEmpty ||
        response.headers['content-type']
                ?.split(';')
                .first
                .trim()
                .toLowerCase() !=
            'application/json') {
      return null;
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && RegExp(r'^[a-z_]{1,64}$').hasMatch(error)) {
          return error;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String _requiredVerifier(String value) {
    if (value.length < 43 ||
        value.length > 128 ||
        !RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(value)) {
      throw const NativeOAuthException('PKCE verifier is invalid.');
    }
    return value;
  }

  static String _requiredToken(String value, String label) {
    if (value.trim() != value ||
        value.length < 16 ||
        value.length > 8192 ||
        RegExp(r'\s').hasMatch(value)) {
      throw NativeOAuthException('$label is invalid.');
    }
    return value;
  }

  static String _requiredOpaque(String value, String label) {
    if (value.trim().isEmpty ||
        value.length > 4096 ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(value)) {
      throw NativeOAuthException('$label is invalid.');
    }
    return value;
  }
}

bool isExactNativeOAuthCallback(Uri uri) =>
    uri.scheme == nativeOAuthRedirectUri.scheme &&
    uri.host == nativeOAuthRedirectUri.host &&
    uri.userInfo.isEmpty &&
    !uri.hasPort &&
    uri.path == nativeOAuthRedirectUri.path &&
    !uri.hasFragment;

String nativePkceS256Challenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');
