import 'dart:async';

import 'package:coordinator_client/coordinator_client.dart';
import 'package:http/http.dart' as http;

import 'native_authorization_router.dart';
import 'native_oauth.dart';
import 'native_session_store.dart';

enum NativeOAuthProgress {
  refreshingSession,
  launchingBrowser,
  awaitingCallback,
  exchangingCode,
}

final class NativeOAuthSessionManager
    implements NativeGatewayAccessTokenProvider {
  NativeOAuthSessionManager(
    this.configuration,
    this._oauthClient,
    this._sessionStore,
    this._callbackRouter,
    this._browserLauncher, {
    DateTime Function()? clock,
    this.onProgress,
    this.expirySkew = const Duration(seconds: 45),
    this.pendingAuthorizationLifetime = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now;

  static const requestedScopes = <String>{
    'inventory:read',
    'resources:act',
    'ports:manage',
  };

  final NativeOAuthConfiguration configuration;
  final NativeOAuthClient _oauthClient;
  final NativeSessionStore _sessionStore;
  final NativeAuthorizationCallbackRouter _callbackRouter;
  final NativeSystemBrowserLauncher _browserLauncher;
  final DateTime Function() _clock;
  final void Function(NativeOAuthProgress progress)? onProgress;
  final Duration expirySkew;
  final Duration pendingAuthorizationLifetime;

  NativeOAuthTokenSet? _tokens;
  Future<String>? _refreshInFlight;
  bool _revocationRequested = false;

  Set<String> get currentScopes => _tokens?.scopes ?? const <String>{};

  Future<bool> restore() async {
    _requireNoRevocationRequest();
    final resumed = await _resumeBufferedAuthorization();
    if (resumed) {
      return true;
    }
    final credential = await _sessionStore.readCredential();
    if (credential == null) {
      return false;
    }
    _validateCredentialBinding(credential);
    if (credential.revocationPending) {
      throw const NativeOAuthException(
        'A previous remote-session revocation must finish before reconnecting.',
        authenticationRequired: true,
      );
    }
    onProgress?.call(NativeOAuthProgress.refreshingSession);
    await forceRefresh();
    return true;
  }

  Future<void> signInInteractively() async {
    _requireNoRevocationRequest();
    final existing = await _sessionStore.readPendingAuthorization();
    NativePendingAuthorization pending;
    NativePkceTransaction transaction;
    if (existing != null &&
        existing.bindingKey == configuration.bindingKey &&
        !_isPendingExpired(existing)) {
      pending = existing;
      final challenge = NativePkceTransaction.generate().challenge;
      transaction = NativePkceTransaction(
        state: pending.state,
        verifier: pending.verifier,
        challenge: challenge,
        createdAt: pending.createdAt,
      );
      // A prior process may already have opened the browser. Resume only from
      // an actual buffered callback; otherwise replace the transaction below.
      final callback = _callbackRouter.takeBufferedCallback(pending.state);
      if (callback != null) {
        await _finishAuthorization(pending, callback);
        return;
      }
    }
    transaction = NativePkceTransaction.generate(clock: _clock);
    pending = NativePendingAuthorization(
      bindingKey: configuration.bindingKey,
      state: transaction.state,
      verifier: transaction.verifier,
      createdAt: transaction.createdAt,
    );
    await _sessionStore.writePendingAuthorization(pending);
    final authorizationUri = _oauthClient.authorizationUri(
      configuration: configuration,
      transaction: transaction,
      scopes: requestedScopes,
    );
    try {
      onProgress?.call(NativeOAuthProgress.launchingBrowser);
      await _browserLauncher.open(authorizationUri);
      onProgress?.call(NativeOAuthProgress.awaitingCallback);
      final callback = await _callbackRouter.waitForCallback(transaction.state);
      await _finishAuthorization(pending, callback);
    } catch (_) {
      await _clearPendingBestEffort();
      rethrow;
    }
  }

  Future<bool> _resumeBufferedAuthorization() async {
    final pending = await _sessionStore.readPendingAuthorization();
    if (pending == null) {
      return false;
    }
    if (pending.bindingKey != configuration.bindingKey ||
        _isPendingExpired(pending)) {
      await _sessionStore.clearPendingAuthorization();
      return false;
    }
    final callback = _callbackRouter.takeBufferedCallback(pending.state);
    if (callback == null) {
      return false;
    }
    await _finishAuthorization(pending, callback);
    return true;
  }

  Future<void> _finishAuthorization(
    NativePendingAuthorization pending,
    Uri callback,
  ) async {
    final code = _validateCallback(callback, pending);
    onProgress?.call(NativeOAuthProgress.exchangingCode);
    final tokens = await _oauthClient.exchangeAuthorizationCode(
      configuration: configuration,
      code: code,
      verifier: pending.verifier,
    );
    try {
      await _persistTokens(tokens);
    } catch (_) {
      await _revokeTokenBestEffort(tokens.refreshToken);
      await _clearCredentialBestEffort();
      rethrow;
    }
    await _sessionStore.clearPendingAuthorization();
  }

  String _validateCallback(Uri callback, NativePendingAuthorization pending) {
    if (!isExactNativeOAuthCallback(callback)) {
      throw const NativeOAuthException(
        'Authorization callback does not match this application.',
        authenticationRequired: true,
      );
    }
    final states = callback.queryParametersAll['state'];
    final codes = callback.queryParametersAll['code'];
    final errors = callback.queryParametersAll['error'];
    final issuers = callback.queryParametersAll['iss'];
    if (states == null ||
        states.length != 1 ||
        states.single != pending.state ||
        issuers == null ||
        issuers.length != 1 ||
        issuers.single != configuration.issuer.toString()) {
      throw const NativeOAuthException(
        'Authorization callback could not be verified.',
        authenticationRequired: true,
      );
    }
    if (errors != null) {
      if (errors.length != 1 || codes != null) {
        throw const NativeOAuthException(
          'Authorization callback is ambiguous.',
          authenticationRequired: true,
        );
      }
      throw NativeOAuthException(
        errors.single == 'access_denied'
            ? 'Browser sign-in was cancelled or denied.'
            : 'Browser sign-in failed: ${errors.single}.',
        authenticationRequired: true,
      );
    }
    if (codes == null || codes.length != 1) {
      throw const NativeOAuthException(
        'Authorization callback does not contain one code.',
        authenticationRequired: true,
      );
    }
    return codes.single;
  }

  bool _isPendingExpired(NativePendingAuthorization pending) =>
      _clock().toUtc().difference(pending.createdAt) >
      pendingAuthorizationLifetime;

  @override
  Future<String?> readAccessToken() async {
    final tokens = _tokens;
    if (tokens != null &&
        tokens.expiresAt.isAfter(_clock().toUtc().add(expirySkew))) {
      return tokens.accessToken;
    }
    return forceRefresh();
  }

  Future<String> forceRefresh({String? rejectedAccessToken}) {
    final current = _tokens;
    if (rejectedAccessToken != null &&
        current != null &&
        current.accessToken != rejectedAccessToken &&
        current.expiresAt.isAfter(_clock().toUtc().add(expirySkew))) {
      return Future<String>.value(current.accessToken);
    }
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _rotateRefreshToken();
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<String> _rotateRefreshToken() async {
    _requireNoRevocationRequest();
    final credential = await _sessionStore.readCredential();
    if (credential == null) {
      throw const NativeOAuthException(
        'Browser sign-in is required.',
        authenticationRequired: true,
      );
    }
    _validateCredentialBinding(credential);
    if (credential.revocationPending) {
      throw const NativeOAuthException(
        'The prior session is fenced for revocation.',
        authenticationRequired: true,
      );
    }
    final NativeOAuthTokenSet tokens;
    try {
      tokens = await _oauthClient.refresh(
        configuration: configuration,
        refreshToken: credential.refreshToken,
      );
    } on NativeOAuthException catch (error) {
      if (error.authenticationRequired) {
        await _sessionStore.clearCredential();
        _tokens = null;
      }
      rethrow;
    }
    try {
      await _persistTokens(
        tokens,
        existingDeviceSessionId: credential.deviceSessionId,
      );
    } catch (_) {
      _tokens = null;
      await _revokeTokenBestEffort(tokens.refreshToken);
      await _clearCredentialBestEffort();
      throw const NativeOAuthException(
        'The rotated refresh token could not be stored securely. Sign in again.',
        authenticationRequired: true,
      );
    }
    return tokens.accessToken;
  }

  Future<void> _persistTokens(
    NativeOAuthTokenSet tokens, {
    String? existingDeviceSessionId,
  }) async {
    final responseDeviceId = tokens.deviceSessionId;
    if (existingDeviceSessionId != null &&
        responseDeviceId != null &&
        existingDeviceSessionId != responseDeviceId) {
      throw const NativeOAuthException(
        'The OAuth device-session identity changed unexpectedly.',
        authenticationRequired: true,
      );
    }
    final credential = NativeRefreshCredential(
      bindingKey: configuration.bindingKey,
      refreshToken: tokens.refreshToken,
      scopes: tokens.scopes,
      updatedAt: _clock().toUtc(),
      deviceSessionId: responseDeviceId ?? existingDeviceSessionId,
    );
    // Secure persistence is the commit point. An access token must never
    // become active while its corresponding rotated refresh token is absent.
    await _sessionStore.writeCredential(credential);
    _tokens = tokens;
  }

  Future<void> bindDeviceSession(String deviceSessionId) async {
    final credential = await _sessionStore.readCredential();
    if (credential == null) {
      throw const NativeOAuthException(
        'The native session is unavailable.',
        authenticationRequired: true,
      );
    }
    _validateCredentialBinding(credential);
    if (credential.deviceSessionId != null &&
        credential.deviceSessionId != deviceSessionId) {
      await _sessionStore.clearCredential();
      _tokens = null;
      throw const NativeOAuthException(
        'The gateway session does not match the stored device session.',
        authenticationRequired: true,
      );
    }
    if (credential.deviceSessionId == null) {
      await _sessionStore.writeCredential(
        credential.copyWith(
          deviceSessionId: deviceSessionId,
          updatedAt: _clock().toUtc(),
        ),
      );
    }
  }

  Future<void> revokeRefreshCredential() async {
    _revocationRequested = true;
    final credential = await _sessionStore.readCredential();
    _tokens = null;
    if (credential == null) {
      await _sessionStore.clearPendingAuthorization();
      return;
    }
    _validateCredentialBinding(credential);
    final fenced = credential.copyWith(
      revocationPending: true,
      updatedAt: _clock().toUtc(),
    );
    try {
      await _sessionStore.writeCredential(fenced);
    } catch (_) {
      throw const NativeOAuthException(
        'The native session could not be fenced for revocation. Its refresh '
        'credential was retained for a later revocation retry.',
        authenticationRequired: true,
      );
    }
    await _oauthClient.revoke(
      configuration: configuration,
      refreshToken: credential.refreshToken,
    );
    await _sessionStore.clearCredential();
    await _sessionStore.clearPendingAuthorization();
  }

  Future<void> clearAfterRemoteRevocation() async {
    _revocationRequested = true;
    _tokens = null;
    await _sessionStore.clearCredential();
    await _sessionStore.clearPendingAuthorization();
  }

  void invalidateAccessToken() {
    _tokens = null;
  }

  void _validateCredentialBinding(NativeRefreshCredential credential) {
    if (credential.bindingKey != configuration.bindingKey) {
      throw const NativeOAuthException(
        'The saved session belongs to a different gateway or OAuth issuer.',
        authenticationRequired: true,
      );
    }
  }

  void _requireNoRevocationRequest() {
    if (_revocationRequested) {
      throw const NativeOAuthException(
        'The native session is fenced for revocation.',
        authenticationRequired: true,
      );
    }
  }

  Future<void> _clearPendingBestEffort() async {
    try {
      await _sessionStore.clearPendingAuthorization();
    } catch (_) {
      // The original browser/callback error is more actionable. The pending
      // record expires and is never an authorization credential.
    }
  }

  Future<void> _clearCredentialBestEffort() async {
    try {
      await _sessionStore.clearCredential();
    } catch (_) {
      // Callers remain signed out in memory and receive an explicit failure.
    }
  }

  Future<void> _revokeTokenBestEffort(String refreshToken) async {
    try {
      await _oauthClient.revoke(
        configuration: configuration,
        refreshToken: refreshToken,
      );
    } catch (_) {
      // Sign-in is still fenced locally. The provider will expire or allow
      // later family revocation if this best-effort request was interrupted.
    }
  }
}

/// Retries one Bearer-authenticated request after a single-flight refresh.
///
/// The native gateway applies idempotency keys to all mutations. A 401 means
/// the request was rejected before dispatch; the exact request and key are
/// retained for the one retry.
final class NativeOAuthRetryClient extends http.BaseClient {
  NativeOAuthRetryClient(
    this._inner,
    this._sessionManager, {
    this.closeInner = true,
  });

  final http.Client _inner;
  final NativeOAuthSessionManager _sessionManager;
  final bool closeInner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      return _inner.send(request);
    }
    final template = _RequestTemplate.fromRequest(request);
    final first = await _inner.send(template.build());
    if (first.statusCode != 401 ||
        !template.headers.containsKey('authorization')) {
      return first;
    }
    await first.stream.drain<void>();
    final rejected = _bearerToken(template.headers['authorization']);
    final String accessToken;
    try {
      accessToken = await _sessionManager.forceRefresh(
        rejectedAccessToken: rejected,
      );
    } on NativeOAuthException catch (error) {
      throw CoordinatorAuthenticationException(error.message);
    }
    return _inner.send(template.build(authorization: 'Bearer $accessToken'));
  }

  @override
  void close() {
    if (closeInner) {
      _inner.close();
    }
  }

  static String? _bearerToken(String? value) {
    if (value == null || !value.startsWith('Bearer ')) {
      return null;
    }
    return value.substring(7);
  }
}

final class _RequestTemplate {
  const _RequestTemplate({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyBytes,
  });

  factory _RequestTemplate.fromRequest(http.Request request) =>
      _RequestTemplate(
        method: request.method,
        url: request.url,
        headers: Map<String, String>.from(request.headers),
        bodyBytes: List<int>.unmodifiable(request.bodyBytes),
      );

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  http.Request build({String? authorization}) {
    final request = http.Request(method, url)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.addAll(headers)
      ..bodyBytes = bodyBytes;
    if (authorization != null) {
      request.headers['authorization'] = authorization;
    }
    return request;
  }
}
