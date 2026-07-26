import 'dart:convert';

import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator/app/app_controller.dart';
import 'package:devcoordinator/app/app_state.dart';
import 'package:devcoordinator/core/auth/native_authorization_router.dart';
import 'package:devcoordinator/core/auth/native_oauth.dart';
import 'package:devcoordinator/core/auth/native_session_store.dart';
import 'package:devcoordinator/core/coordinator/legacy_coordinator_service.dart';
import 'package:devcoordinator/core/storage/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void main() {
  group('production native gateway boundary', () {
    test('cold restore rejects a foreign persisted gateway offline', () async {
      var requests = 0;
      final store = _RecordingSessionStore();
      final controller = AppController(
        settingsStore: FakeSettingsStore(
          const PersistedAppSettings(
            updateChecksEnabled: false,
            connection: StoredConnectionProfile(
              kind: StoredConnectionKind.nativeGatewayV2,
              baseUrl: 'https://gateway.example.test/api/v2',
              label: 'Saved gateway',
            ),
          ),
        ),
        tokenStore: FakeTokenStore(),
        coordinatorFactory: _factory(
          store: store,
          handler: (_) async {
            requests += 1;
            return http.Response('', 500);
          },
        ),
        updateService: FakeUpdateService(),
        packageInfoLoader: packageInfoFixture,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.state.isConnected, isFalse);
      expect(
        controller.state.connectionError,
        contains('canonical production'),
      );
      expect(requests, 0);
      expect(store.credentialReads, 0);
    });

    test('rejects a foreign saved gateway before HTTP dispatch', () async {
      var requests = 0;
      final store = _RecordingSessionStore();
      final factory = _factory(
        store: store,
        handler: (_) async {
          requests += 1;
          return http.Response('', 500);
        },
      );

      await expectLater(
        factory.connect(
          profile: const StoredConnectionProfile(
            kind: StoredConnectionKind.nativeGatewayV2,
            baseUrl: 'https://gateway.example.test/api/v2',
            label: 'Saved gateway',
          ),
        ),
        throwsA(isA<CoordinatorEndpointException>()),
      );

      expect(requests, 0);
      expect(store.credentialReads, 0);
    });

    test('rejects a non-exact saved gateway before revocation reads', () async {
      var requests = 0;
      final store = _RecordingSessionStore();
      final factory = _factory(
        store: store,
        handler: (_) async {
          requests += 1;
          return http.Response('', 500);
        },
      );

      await expectLater(
        factory.revokeStoredNativeSession(
          const StoredConnectionProfile(
            kind: StoredConnectionKind.nativeGatewayV2,
            baseUrl: 'https://console.classified.guru/api/v2/',
            label: 'Saved gateway',
          ),
        ),
        throwsA(isA<CoordinatorEndpointException>()),
      );

      expect(requests, 0);
      expect(store.credentialReads, 0);
    });

    test('composes the exact production gateway meta endpoint', () async {
      final requests = <http.Request>[];
      final factory = _factory(
        store: _RecordingSessionStore(),
        handler: (request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(_metaFixture),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        },
      );

      await expectLater(
        factory.connect(
          profile: const StoredConnectionProfile(
            kind: StoredConnectionKind.nativeGatewayV2,
            baseUrl: 'https://console.classified.guru/api/v2',
            label: 'DevCoordinator',
          ),
        ),
        throwsA(
          isA<NativeOAuthException>().having(
            (error) => error.authenticationRequired,
            'authenticationRequired',
            isTrue,
          ),
        ),
      );

      expect(requests, hasLength(1));
      expect(
        requests.single.url,
        Uri.parse('https://console.classified.guru/api/v2/meta'),
      );
    });

    test(
      'cold pending revocation revokes the stored token without refreshing',
      () async {
        final requests = <http.Request>[];
        final credential = NativeRefreshCredential(
          bindingKey: _configurationBindingKey,
          refreshToken: 'r' * 40,
          scopes: const <String>{'inventory:read'},
          updatedAt: DateTime.utc(2026),
          deviceSessionId: 'device-1',
        );
        final store = _RecordingSessionStore(credential: credential);
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(
            updateChecksEnabled: false,
            credentialCleanupPending: true,
            connection: StoredConnectionProfile(
              kind: StoredConnectionKind.nativeGatewayV2,
              baseUrl: 'https://console.classified.guru/api/v2',
              label: 'DevCoordinator',
            ),
          ),
        );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: FakeTokenStore(),
          coordinatorFactory: _factory(
            store: store,
            handler: (request) async {
              requests.add(request);
              if (request.url.path == '/api/v2/meta') {
                return http.Response(
                  jsonEncode(_metaFixture),
                  200,
                  headers: const <String, String>{
                    'content-type': 'application/json',
                  },
                );
              }
              if (request.url.path == '/oauth/revoke') {
                expect(request.bodyFields['token'], credential.refreshToken);
                return http.Response('', 204);
              }
              return http.Response('', 500);
            },
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(requests.map((request) => request.url.path), <String>[
          '/api/v2/meta',
          '/oauth/revoke',
        ]);
        expect(
          requests.where(
            (request) =>
                request.url.path == '/oauth/token' ||
                request.url.path == '/api/v2/session',
          ),
          isEmpty,
        );
        expect(store.credential, isNull);
        expect(settingsStore.value.connection, isNull);
        expect(settingsStore.value.credentialCleanupPending, isFalse);
        expect(controller.state.connectionPhase, ConnectionPhase.disconnected);
      },
    );

    test(
      'cold pending revocation fence failure cannot dispatch a refresh',
      () async {
        final requests = <http.Request>[];
        final credential = NativeRefreshCredential(
          bindingKey: _configurationBindingKey,
          refreshToken: 'r' * 40,
          scopes: const <String>{'inventory:read'},
          updatedAt: DateTime.utc(2026),
          deviceSessionId: 'device-1',
        );
        final store = _RecordingSessionStore(
          credential: credential,
          writeCredentialError: StateError('secure storage unavailable'),
        );
        const profile = StoredConnectionProfile(
          kind: StoredConnectionKind.nativeGatewayV2,
          baseUrl: 'https://console.classified.guru/api/v2',
          label: 'DevCoordinator',
        );
        final settingsStore = FakeSettingsStore(
          const PersistedAppSettings(
            updateChecksEnabled: false,
            credentialCleanupPending: true,
            connection: profile,
          ),
        );
        final controller = AppController(
          settingsStore: settingsStore,
          tokenStore: FakeTokenStore(),
          coordinatorFactory: _factory(
            store: store,
            handler: (request) async {
              requests.add(request);
              return http.Response('', 500);
            },
          ),
          updateService: FakeUpdateService(),
          packageInfoLoader: packageInfoFixture,
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(requests, isEmpty);
        expect(store.credential, same(credential));
        expect(store.credential?.revocationPending, isFalse);
        expect(settingsStore.value.connection, same(profile));
        expect(settingsStore.value.credentialCleanupPending, isTrue);
        expect(controller.state.connectionPhase, ConnectionPhase.revoked);
        expect(
          controller.state.connectionError,
          contains('secure storage unavailable'),
        );
      },
    );
  });
}

PlatformCoordinatorServiceFactory _factory({
  required _RecordingSessionStore store,
  required Future<http.Response> Function(http.Request request) handler,
}) {
  return PlatformCoordinatorServiceFactory(
    supportsLegacyLocalConnection: false,
    clientFactory: () => MockClient(handler),
    nativeSessionStore: store,
    callbackRouter: _NoopCallbackRouter(),
    browserLauncher: const _NoopBrowser(),
    clientVersionLoader: () async => '0.2.0',
  );
}

const _metaFixture = <String, Object?>{
  'contractVersion': '2.0',
  'serverVersion': '1.8.0',
  'minimumClientVersion': '0.2.0',
  'issuer': 'https://console.classified.guru',
  'authorizationEndpoint': 'https://console.classified.guru/oauth/authorize',
  'tokenEndpoint': 'https://console.classified.guru/oauth/token',
  'revocationEndpoint': 'https://console.classified.guru/oauth/revoke',
  'publicClientId': 'io.github.holyglory.devcoordinator',
  'pkceMethods': <String>['S256'],
  'capabilities': <String>['inventory.read'],
};

final _configurationBindingKey = NativeOAuthConfiguration(
  gatewayEndpoint: Uri.parse('https://console.classified.guru/api/v2'),
  issuer: Uri.parse('https://console.classified.guru'),
  authorizationEndpoint: Uri.parse(
    'https://console.classified.guru/oauth/authorize',
  ),
  tokenEndpoint: Uri.parse('https://console.classified.guru/oauth/token'),
  revocationEndpoint: Uri.parse('https://console.classified.guru/oauth/revoke'),
  clientId: nativeOAuthClientId,
  pkceMethods: const <String>{'S256'},
).bindingKey;

final class _RecordingSessionStore implements NativeSessionStore {
  _RecordingSessionStore({this.credential, this.writeCredentialError});

  NativeRefreshCredential? credential;
  final Object? writeCredentialError;
  int credentialReads = 0;
  int credentialWrites = 0;
  int credentialClears = 0;

  @override
  Future<void> clearCredential() async {
    credentialClears += 1;
    credential = null;
  }

  @override
  Future<void> clearPendingAuthorization() async {}

  @override
  Future<NativeRefreshCredential?> readCredential() async {
    credentialReads += 1;
    return credential;
  }

  @override
  Future<NativePendingAuthorization?> readPendingAuthorization() async => null;

  @override
  Future<void> writeCredential(NativeRefreshCredential credential) async {
    credentialWrites += 1;
    final error = writeCredentialError;
    if (error != null) throw error;
    this.credential = credential;
  }

  @override
  Future<void> writePendingAuthorization(
    NativePendingAuthorization authorization,
  ) async {}
}

final class _NoopCallbackRouter implements NativeAuthorizationCallbackRouter {
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
  }) {
    throw StateError('No interactive callback was expected.');
  }
}

final class _NoopBrowser implements NativeSystemBrowserLauncher {
  const _NoopBrowser();

  @override
  Future<void> open(Uri uri) {
    throw StateError('No browser launch was expected.');
  }
}
