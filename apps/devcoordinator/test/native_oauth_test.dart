import 'dart:convert';

import 'package:devcoordinator/core/auth/native_authorization_router.dart';
import 'package:devcoordinator/core/auth/native_oauth.dart';
import 'package:devcoordinator/core/auth/native_oauth_session_manager.dart';
import 'package:devcoordinator/core/auth/native_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('PKCE and metadata', () {
    test('matches the RFC 7636 S256 vector', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

      expect(
        nativePkceS256Challenge(verifier),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('generates bounded URL-safe state and verifier', () {
      final first = NativePkceTransaction.generate();
      final second = NativePkceTransaction.generate();

      expect(first.state, isNot(second.state));
      expect(first.verifier, isNot(second.verifier));
      expect(first.state, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(first.verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43,128}$')));
      expect(first.challenge, nativePkceS256Challenge(first.verifier));
      expect(first.challenge, isNot(contains('=')));
    });

    test('rejects cross-origin and non-HTTPS discovery', () {
      expect(
        () => NativeOAuthConfiguration(
          gatewayEndpoint: Uri.parse('https://console.classified.guru/api/v2'),
          issuer: Uri.parse('https://console.classified.guru'),
          authorizationEndpoint: Uri.parse(
            'https://login.attacker.invalid/authorize',
          ),
          tokenEndpoint: Uri.parse(
            'https://console.classified.guru/oauth/token',
          ),
          revocationEndpoint: Uri.parse(
            'https://console.classified.guru/oauth/revoke',
          ),
          clientId: nativeOAuthClientId,
          pkceMethods: const <String>{'S256'},
        ),
        throwsA(isA<NativeOAuthException>()),
      );
      expect(
        () => NativeOAuthConfiguration(
          gatewayEndpoint: Uri.parse('http://console.classified.guru/api/v2'),
          issuer: Uri.parse('https://console.classified.guru'),
          authorizationEndpoint: Uri.parse(
            'https://console.classified.guru/oauth/authorize',
          ),
          tokenEndpoint: Uri.parse(
            'https://console.classified.guru/oauth/token',
          ),
          revocationEndpoint: Uri.parse(
            'https://console.classified.guru/oauth/revoke',
          ),
          clientId: nativeOAuthClientId,
          pkceMethods: const <String>{'S256'},
        ),
        throwsA(isA<NativeOAuthException>()),
      );
    });

    test('authorization URL contains PKCE and no client secret', () {
      final transaction = NativePkceTransaction.generate();
      final client = NativeOAuthClient(
        MockClient((_) async => http.Response('', 500)),
      );

      final uri = client.authorizationUri(
        configuration: configuration(),
        transaction: transaction,
        scopes: const <String>{'resources:act', 'inventory:read'},
      );

      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['client_id'], nativeOAuthClientId);
      expect(
        uri.queryParameters['redirect_uri'],
        nativeOAuthRedirectUri.toString(),
      );
      expect(uri.queryParameters['state'], transaction.state);
      expect(uri.queryParameters['code_challenge'], transaction.challenge);
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters, isNot(contains('client_secret')));
    });

    test('accepts only the exact app callback', () {
      expect(isExactNativeOAuthCallback(nativeOAuthRedirectUri), isTrue);
      expect(
        isExactNativeOAuthCallback(
          Uri.parse('io.github.holyglory.devcoordinator:/oauth/callback'),
        ),
        isFalse,
      );
      expect(
        isExactNativeOAuthCallback(
          Uri.parse('io.github.holyglory.devcoordinator://oauth:443/callback'),
        ),
        isFalse,
      );
      expect(
        isExactNativeOAuthCallback(
          Uri.parse('io.github.holyglory.devcoordinator://other/callback'),
        ),
        isFalse,
      );
      expect(
        isExactNativeOAuthCallback(
          Uri.parse(
            'io.github.holyglory.devcoordinator://oauth/callback#code=x',
          ),
        ),
        isFalse,
      );
    });
  });

  group('rotating session manager', () {
    test(
      'refresh is single-flight and commits rotation before access',
      () async {
        final store = MemoryNativeSessionStore()
          ..credential = NativeRefreshCredential(
            bindingKey: configuration().bindingKey,
            refreshToken: 'r' * 40,
            scopes: const <String>{'inventory:read'},
            updatedAt: DateTime.utc(2026),
            deviceSessionId: 'device-1',
          );
        var requests = 0;
        final manager = managerWith(
          store: store,
          client: MockClient((request) async {
            requests += 1;
            expect(request.bodyFields['refresh_token'], 'r' * 40);
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return tokenResponse(
              accessToken: 'a' * 40,
              refreshToken: 'n' * 40,
              deviceSessionId: 'device-1',
            );
          }),
        );

        final tokens = await Future.wait<String?>(<Future<String?>>[
          manager.readAccessToken(),
          manager.readAccessToken(),
          manager.readAccessToken(),
        ]);

        expect(tokens, everyElement('a' * 40));
        expect(requests, 1);
        expect(store.writeCredentialCount, 1);
        expect(store.credential?.refreshToken, 'n' * 40);
        expect(await manager.readAccessToken(), 'a' * 40);
        expect(requests, 1);
      },
    );

    test('access_denied clears the saved credential immediately', () async {
      final store = MemoryNativeSessionStore()
        ..credential = NativeRefreshCredential(
          bindingKey: configuration().bindingKey,
          refreshToken: 'r' * 40,
          scopes: const <String>{'inventory:read'},
          updatedAt: DateTime.utc(2026),
        );
      final manager = managerWith(
        store: store,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{'error': 'access_denied'}),
            400,
            headers: const <String, String>{'content-type': 'application/json'},
          ),
        ),
      );

      await expectLater(
        manager.readAccessToken(),
        throwsA(
          isA<NativeOAuthException>().having(
            (error) => error.authenticationRequired,
            'authenticationRequired',
            isTrue,
          ),
        ),
      );
      expect(store.credential, isNull);
      expect(store.clearCredentialCount, 1);
    });

    test(
      'failed secure rotation revokes the new token and signs out',
      () async {
        final store = MemoryNativeSessionStore()
          ..credential = NativeRefreshCredential(
            bindingKey: configuration().bindingKey,
            refreshToken: 'r' * 40,
            scopes: const <String>{'inventory:read'},
            updatedAt: DateTime.utc(2026),
          )
          ..writeCredentialError = StateError('keychain locked');
        var requests = 0;
        final manager = managerWith(
          store: store,
          client: MockClient((request) async {
            requests += 1;
            if (request.url.path == '/oauth/revoke') {
              expect(request.bodyFields['token'], 'n' * 40);
              return http.Response('', 204);
            }
            return tokenResponse(accessToken: 'a' * 40, refreshToken: 'n' * 40);
          }),
        );

        await expectLater(
          manager.readAccessToken(),
          throwsA(
            isA<NativeOAuthException>().having(
              (error) => error.authenticationRequired,
              'authenticationRequired',
              isTrue,
            ),
          ),
        );

        expect(requests, 2);
        expect(store.credential, isNull);
      },
    );

    test(
      'failed revocation fence preserves the live credential for retry',
      () async {
        final original = NativeRefreshCredential(
          bindingKey: configuration().bindingKey,
          refreshToken: 'r' * 40,
          scopes: const <String>{'inventory:read'},
          updatedAt: DateTime.utc(2026),
          deviceSessionId: 'device-1',
        );
        final store = MemoryNativeSessionStore()
          ..credential = original
          ..writeCredentialError = StateError('keychain locked');
        var revocations = 0;
        final manager = managerWith(
          store: store,
          client: MockClient((request) async {
            revocations += 1;
            expect(request.url.path, '/oauth/revoke');
            expect(request.bodyFields['token'], original.refreshToken);
            return http.Response('', 204);
          }),
        );

        await expectLater(
          manager.revokeRefreshCredential(),
          throwsA(
            isA<NativeOAuthException>().having(
              (error) => error.authenticationRequired,
              'authenticationRequired',
              isTrue,
            ),
          ),
        );

        expect(store.credential, same(original));
        expect(store.credential?.revocationPending, isFalse);
        expect(store.clearCredentialCount, 0);
        expect(revocations, 0);

        await expectLater(
          manager.readAccessToken(),
          throwsA(
            isA<NativeOAuthException>().having(
              (error) => error.authenticationRequired,
              'authenticationRequired',
              isTrue,
            ),
          ),
        );
        expect(store.credential, same(original));
        expect(revocations, 0);

        store.writeCredentialError = null;
        await manager.revokeRefreshCredential();

        expect(revocations, 1);
        expect(store.credential, isNull);
        expect(store.clearCredentialCount, 1);
      },
    );

    test(
      'failed OAuth revocation retains a fenced credential for retry',
      () async {
        final store = MemoryNativeSessionStore()
          ..credential = NativeRefreshCredential(
            bindingKey: configuration().bindingKey,
            refreshToken: 'r' * 40,
            scopes: const <String>{'inventory:read'},
            updatedAt: DateTime.utc(2026),
            deviceSessionId: 'device-1',
          );
        var failRevocation = true;
        final manager = managerWith(
          store: store,
          client: MockClient((request) async {
            expect(request.url.path, '/oauth/revoke');
            if (failRevocation) {
              return http.Response('', 503);
            }
            return http.Response('', 204);
          }),
        );

        await expectLater(
          manager.revokeRefreshCredential(),
          throwsA(isA<NativeOAuthException>()),
        );

        expect(store.credential?.refreshToken, 'r' * 40);
        expect(store.credential?.revocationPending, isTrue);
        expect(store.clearCredentialCount, 0);

        failRevocation = false;
        await manager.revokeRefreshCredential();

        expect(store.credential, isNull);
        expect(store.clearCredentialCount, 1);
      },
    );

    test('interactive sign-in validates state and persists rotation', () async {
      final store = MemoryNativeSessionStore();
      final router = CallbackRouter();
      final browser = RecordingBrowser();
      final progress = <NativeOAuthProgress>[];
      final client = MockClient((request) async {
        expect(request.bodyFields['grant_type'], 'authorization_code');
        expect(request.bodyFields, isNot(contains('client_secret')));
        return tokenResponse(
          accessToken: 'a' * 40,
          refreshToken: 'r' * 40,
          deviceSessionId: 'device-1',
        );
      });
      final manager = NativeOAuthSessionManager(
        configuration(),
        NativeOAuthClient(client),
        store,
        router,
        browser,
        onProgress: progress.add,
      );

      await manager.signInInteractively();

      expect(browser.opened, hasLength(1));
      expect(store.pending, isNull);
      expect(store.credential?.refreshToken, 'r' * 40);
      expect(await manager.readAccessToken(), 'a' * 40);
      expect(progress, <NativeOAuthProgress>[
        NativeOAuthProgress.launchingBrowser,
        NativeOAuthProgress.awaitingCallback,
        NativeOAuthProgress.exchangingCode,
      ]);
    });

    test('wrong-state callback cannot consume a pending flow', () async {
      final store = MemoryNativeSessionStore();
      final router = CallbackRouter(stateOverride: 'wrong-state');
      final manager = NativeOAuthSessionManager(
        configuration(),
        NativeOAuthClient(
          MockClient((_) async => throw StateError('must not exchange')),
        ),
        store,
        router,
        RecordingBrowser(),
      );

      await expectLater(
        manager.signInInteractively(),
        throwsA(isA<NativeOAuthException>()),
      );
      expect(store.credential, isNull);
      expect(store.pending, isNull);
    });

    test('callback without the exact RFC 9207 issuer is rejected', () async {
      final store = MemoryNativeSessionStore();
      var exchanges = 0;
      final manager = NativeOAuthSessionManager(
        configuration(),
        NativeOAuthClient(
          MockClient((_) async {
            exchanges += 1;
            return tokenResponse(accessToken: 'a' * 40, refreshToken: 'r' * 40);
          }),
        ),
        store,
        CallbackRouter(includeIssuer: false),
        RecordingBrowser(),
      );

      await expectLater(
        manager.signInInteractively(),
        throwsA(
          isA<NativeOAuthException>().having(
            (error) => error.authenticationRequired,
            'authenticationRequired',
            isTrue,
          ),
        ),
      );

      expect(exchanges, 0);
      expect(store.credential, isNull);
      expect(store.pending, isNull);
    });
  });
}

NativeOAuthConfiguration configuration() => NativeOAuthConfiguration(
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

NativeOAuthSessionManager managerWith({
  required MemoryNativeSessionStore store,
  required http.Client client,
}) {
  return NativeOAuthSessionManager(
    configuration(),
    NativeOAuthClient(client),
    store,
    CallbackRouter(),
    RecordingBrowser(),
  );
}

http.Response tokenResponse({
  required String accessToken,
  required String refreshToken,
  String? deviceSessionId,
}) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'token_type': 'Bearer',
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_in': 3600,
      'scope': 'inventory:read resources:act ports:manage',
      'device_session_id': ?deviceSessionId,
    }),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

final class MemoryNativeSessionStore implements NativeSessionStore {
  NativeRefreshCredential? credential;
  NativePendingAuthorization? pending;
  int writeCredentialCount = 0;
  int clearCredentialCount = 0;
  Object? writeCredentialError;

  @override
  Future<void> clearCredential() async {
    clearCredentialCount += 1;
    credential = null;
  }

  @override
  Future<void> clearPendingAuthorization() async {
    pending = null;
  }

  @override
  Future<NativeRefreshCredential?> readCredential() async => credential;

  @override
  Future<NativePendingAuthorization?> readPendingAuthorization() async =>
      pending;

  @override
  Future<void> writeCredential(NativeRefreshCredential value) async {
    writeCredentialCount += 1;
    final error = writeCredentialError;
    if (error != null) throw error;
    credential = value;
  }

  @override
  Future<void> writePendingAuthorization(
    NativePendingAuthorization value,
  ) async {
    pending = value;
  }
}

final class CallbackRouter implements NativeAuthorizationCallbackRouter {
  CallbackRouter({this.stateOverride, this.includeIssuer = true});

  final String? stateOverride;
  final bool includeIssuer;

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
  }) async {
    return nativeOAuthRedirectUri.replace(
      queryParameters: <String, String>{
        'state': stateOverride ?? state,
        'code': 'authorization-code',
        if (includeIssuer) 'iss': configuration().issuer.toString(),
      },
    );
  }
}

final class RecordingBrowser implements NativeSystemBrowserLauncher {
  final List<Uri> opened = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    opened.add(uri);
  }
}
