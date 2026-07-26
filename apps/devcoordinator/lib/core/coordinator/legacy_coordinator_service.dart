import 'package:coordinator_client/coordinator_client.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../app/app_services.dart';
import '../auth/native_authorization_router.dart';
import '../auth/native_oauth.dart';
import '../auth/native_oauth_session_manager.dart';
import '../auth/native_session_store.dart';
import '../platform/platform_support.dart';
import '../storage/settings_store.dart';
import 'native_gateway_policy.dart';
import 'native_coordinator_service.dart';

/// Creates the only connection supported by the current server: its local,
/// loopback-only v1 API. Native v2 deliberately has no placeholder transport.
final class PlatformCoordinatorServiceFactory
    implements AppCoordinatorServiceFactory, NativeStoredSessionRevoker {
  PlatformCoordinatorServiceFactory({
    bool? supportsLegacyLocalConnection,
    http.Client Function()? clientFactory,
    NativeSessionStore? nativeSessionStore,
    NativeAuthorizationCallbackRouter? callbackRouter,
    NativeSystemBrowserLauncher? browserLauncher,
    Future<String> Function()? clientVersionLoader,
  }) : _supportsLegacyLocalConnection =
           supportsLegacyLocalConnection ??
           PlatformSupport.supportsLegacyLocalConnection,
       _clientFactory = clientFactory ?? http.Client.new,
       _nativeSessionStore = nativeSessionStore ?? PlatformNativeSessionStore(),
       _callbackRouter =
           callbackRouter ?? PlatformNativeAuthorizationCallbackRouter(),
       _browserLauncher =
           browserLauncher ?? const PlatformNativeSystemBrowserLauncher(),
       _clientVersionLoader =
           clientVersionLoader ??
           (() async => (await PackageInfo.fromPlatform()).version);

  final bool _supportsLegacyLocalConnection;
  final http.Client Function() _clientFactory;
  final NativeSessionStore _nativeSessionStore;
  final NativeAuthorizationCallbackRouter _callbackRouter;
  final NativeSystemBrowserLauncher _browserLauncher;
  final Future<String> Function() _clientVersionLoader;

  @override
  Future<AppCoordinatorService> connect({
    required StoredConnectionProfile profile,
    String? credential,
    bool interactive = false,
    void Function(CoordinatorConnectionProgress progress)? onProgress,
  }) async {
    if (profile.kind == StoredConnectionKind.nativeGatewayV2) {
      return _connectNative(
        profile,
        interactive: interactive,
        onProgress: onProgress,
      );
    }
    if (!_supportsLegacyLocalConnection) {
      throw UnsupportedError(
        'Legacy v1 is available only to the macOS app on the coordinator '
        'host. Android, Windows, and off-host clients require native gateway '
        'v2.',
      );
    }

    final uri = Uri.tryParse(profile.baseUrl);
    if (uri == null) {
      throw const FormatException('The coordinator endpoint is not a URL.');
    }
    final endpoint = CoordinatorEndpoint.legacyV1(uri);
    final normalizedCredential = credential?.trim() ?? '';
    if (normalizedCredential.isEmpty) {
      throw const FormatException('The coordinator token is required.');
    }
    final actor = CoordinatorActor(
      _required(profile.agent, 'Action attribution is required.'),
    );
    final gateway = LegacyLoopbackV1Client(
      endpoint: endpoint,
      tokenProvider: CallbackCoordinatorTokenProvider(
        () async => normalizedCredential,
      ),
      httpClient: _clientFactory(),
      closeHttpClient: true,
    );
    try {
      final meta = await gateway.readMeta();
      if (meta.apiMajor != 1 ||
          !meta.supports(CoordinatorCapability.inventoryRead)) {
        throw StateError(
          'The selected connection contract does not support inventory.',
        );
      }
      return LegacyCoordinatorService(gateway, actor, meta);
    } catch (_) {
      gateway.close();
      rethrow;
    }
  }

  @override
  Future<void> revokeStoredNativeSession(
    StoredConnectionProfile profile,
  ) async {
    if (profile.kind != StoredConnectionKind.nativeGatewayV2) {
      throw ArgumentError.value(
        profile.kind,
        'profile.kind',
        'must be nativeGatewayV2',
      );
    }
    final endpoint = canonicalNativeGatewayEndpoint(profile);
    final stored = await _nativeSessionStore.readCredential();
    if (stored != null && !stored.revocationPending) {
      await _nativeSessionStore.writeCredential(
        stored.copyWith(
          revocationPending: true,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    final meta = await _readNativeMeta(endpoint);
    final configuration = _oauthConfiguration(endpoint, meta);
    final httpClient = _clientFactory();
    try {
      final manager = NativeOAuthSessionManager(
        configuration,
        NativeOAuthClient(httpClient),
        _nativeSessionStore,
        _callbackRouter,
        _browserLauncher,
      );
      await manager.revokeRefreshCredential();
    } finally {
      httpClient.close();
    }
  }

  Future<AppCoordinatorService> _connectNative(
    StoredConnectionProfile profile, {
    required bool interactive,
    void Function(CoordinatorConnectionProgress progress)? onProgress,
  }) async {
    onProgress?.call(CoordinatorConnectionProgress.validatingEndpoint);
    final endpoint = canonicalNativeGatewayEndpoint(profile);
    final meta = await _readNativeMeta(endpoint);
    if (!meta.capabilities.supports(NativeGatewayCapability.inventoryRead)) {
      throw const CoordinatorCapabilityException(
        'The native gateway does not advertise inventory.read.',
      );
    }
    final minimumVersion = _parseVersion(
      meta.minimumClientVersion,
      'minimum client version',
    );
    final installedVersion = _parseVersion(
      await _clientVersionLoader(),
      'installed client version',
    );
    if (installedVersion < minimumVersion) {
      throw StateError(
        'This gateway requires app version $minimumVersion or newer.',
      );
    }
    final configuration = _oauthConfiguration(endpoint, meta);
    await _callbackRouter.initialize();
    onProgress?.call(CoordinatorConnectionProgress.refreshingSession);
    final authenticatedHttp = _clientFactory();
    final manager = NativeOAuthSessionManager(
      configuration,
      NativeOAuthClient(authenticatedHttp),
      _nativeSessionStore,
      _callbackRouter,
      _browserLauncher,
      onProgress: (progress) {
        onProgress?.call(switch (progress) {
          NativeOAuthProgress.refreshingSession =>
            CoordinatorConnectionProgress.refreshingSession,
          NativeOAuthProgress.launchingBrowser =>
            CoordinatorConnectionProgress.launchingBrowser,
          NativeOAuthProgress.awaitingCallback =>
            CoordinatorConnectionProgress.awaitingCallback,
          NativeOAuthProgress.exchangingCode =>
            CoordinatorConnectionProgress.exchangingCode,
        });
      },
    );
    NativeGatewayV2CoreClient? gateway;
    try {
      final restored = await manager.restore();
      if (!restored) {
        if (!interactive) {
          throw const NativeOAuthException(
            'Browser sign-in is required for this saved gateway.',
            authenticationRequired: true,
          );
        }
        await manager.signInInteractively();
      }
      final retryingHttp = NativeOAuthRetryClient(authenticatedHttp, manager);
      gateway = NativeGatewayV2CoreClient(
        endpoint: endpoint,
        accessTokenProvider: manager,
        httpClient: retryingHttp,
        closeHttpClient: true,
      );
      final session = await gateway.readSession();
      if (!session.expiresAt.isAfter(DateTime.now().toUtc())) {
        await manager.clearAfterRemoteRevocation();
        throw const CoordinatorAuthenticationException(
          'The native gateway session has expired.',
        );
      }
      await manager.bindDeviceSession(session.deviceSessionId);
      final service = NativeGatewayCoordinatorService(
        gateway,
        manager,
        session,
        nativeMeta: meta,
      );
      gateway = null;
      return service;
    } catch (_) {
      if (gateway != null) {
        gateway.close();
      } else {
        authenticatedHttp.close();
      }
      rethrow;
    }
  }

  Future<NativeGatewayMeta> _readNativeMeta(
    CoordinatorEndpoint endpoint,
  ) async {
    final bootstrapHttp = _clientFactory();
    final bootstrap = NativeGatewayV2CoreClient(
      endpoint: endpoint,
      accessTokenProvider: CallbackNativeGatewayAccessTokenProvider(
        () async => null,
      ),
      httpClient: bootstrapHttp,
      closeHttpClient: true,
    );
    try {
      return (await bootstrap.readMeta()).value;
    } finally {
      bootstrap.close();
    }
  }

  static NativeOAuthConfiguration _oauthConfiguration(
    CoordinatorEndpoint endpoint,
    NativeGatewayMeta meta,
  ) {
    return NativeOAuthConfiguration(
      gatewayEndpoint: endpoint.uri,
      issuer: meta.issuer,
      authorizationEndpoint: meta.authorizationEndpoint,
      tokenEndpoint: meta.tokenEndpoint,
      revocationEndpoint: meta.revocationEndpoint,
      clientId: meta.publicClientId,
      pkceMethods: meta.pkceMethods.map((method) => method.wireValue),
    );
  }

  static Version _parseVersion(String value, String label) {
    try {
      return Version.parse(value);
    } on FormatException {
      throw CoordinatorProtocolException('The $label is not valid SemVer.');
    }
  }

  static String _required(String? value, String message) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) throw FormatException(message);
    return normalized;
  }
}

final class LegacyCoordinatorService implements AppCoordinatorService {
  LegacyCoordinatorService(this._gateway, this._actor, this._meta);

  final CoordinatorGateway _gateway;
  final CoordinatorActor _actor;
  final CoordinatorMeta _meta;

  @override
  bool supports(CoordinatorCapability capability) => _meta.supports(capability);

  @override
  Future<CoordinatorInventory> loadInventory() => _gateway.readInventory();

  @override
  Future<CoordinatorActionResult> actOnServer(
    CoordinatorServer server,
    CoordinatorResourceAction action,
  ) {
    if (action == CoordinatorResourceAction.start) {
      final port = server.port;
      if (port == null) {
        throw StateError(
          'Starting ${server.name} requires an explicit committed port.',
        );
      }
      if (server.arguments.isEmpty) {
        throw StateError(
          'Starting ${server.name} requires committed launch arguments.',
        );
      }
      return _gateway.startServer(
        CoordinatorServerStartRequest(
          target: CoordinatorServerLaunchTarget(
            repoId: _requiredOwnership(server.repoId, 'repository'),
            projectRoot: _requiredOwnership(server.projectRoot, 'project root'),
            name: server.name,
          ),
          actor: _actor,
          arguments: server.arguments,
          range: CoordinatorPortRange(port, port),
          cwd: server.cwd,
          preferredPort: port,
          healthUrl: server.healthUrl,
          leaseId: server.leaseId,
        ),
      );
    }
    return _gateway.actOnServer(
      target: CoordinatorServerTarget(
        id: server.id,
        repoId: _requiredOwnership(server.repoId, 'repository'),
        projectRoot: _requiredOwnership(server.projectRoot, 'project root'),
        name: server.name,
      ),
      actor: _actor,
      action: action,
    );
  }

  @override
  Future<CoordinatorActionResult> actOnProject(
    CoordinatorProject project,
    CoordinatorProjectAction action,
  ) {
    return _gateway.actOnProject(
      target: CoordinatorProjectTarget(
        repoId: project.id,
        canonicalRoot: project.canonicalRoot,
      ),
      actor: _actor,
      action: action,
    );
  }

  @override
  Future<CoordinatorActionResult> actOnContainer(
    CoordinatorContainer container,
    CoordinatorResourceAction action,
  ) {
    return _gateway.actOnContainer(
      target: _containerTarget(container),
      actor: _actor,
      action: action,
    );
  }

  @override
  Future<CoordinatorLogResult> readServerLogs(
    CoordinatorServer server, {
    int tail = 200,
  }) {
    return _gateway.readServerLogs(
      CoordinatorServerTarget(
        id: server.id,
        repoId: _requiredOwnership(server.repoId, 'repository'),
        projectRoot: _requiredOwnership(server.projectRoot, 'project root'),
        name: server.name,
      ),
      tail: tail,
    );
  }

  @override
  Future<CoordinatorLogResult> readContainerLogs(
    CoordinatorContainer container, {
    int tail = 200,
  }) {
    return _gateway.readContainerLogs(_containerTarget(container), tail: tail);
  }

  @override
  Future<CoordinatorLease> leasePort({
    required CoordinatorProject project,
    required CoordinatorServer server,
    required int firstPort,
    required int lastPort,
    int? preferredPort,
    Duration? ttl,
    String? purpose,
  }) {
    return _gateway.leasePort(
      CoordinatorPortLeaseRequest(
        project: CoordinatorProjectTarget(
          repoId: project.id,
          canonicalRoot: project.canonicalRoot,
        ),
        server: CoordinatorServerTarget(
          id: server.id,
          repoId: _requiredOwnership(server.repoId, 'repository'),
          projectRoot: _requiredOwnership(server.projectRoot, 'project root'),
          name: server.name,
        ),
        actor: _actor,
        range: CoordinatorPortRange(firstPort, lastPort),
        preferredPort: preferredPort,
        ttl: ttl,
        purpose: purpose?.trim().isEmpty ?? true ? null : purpose!.trim(),
      ),
    );
  }

  @override
  Future<CoordinatorActionResult> releasePort(CoordinatorLease lease) {
    return _gateway.releasePort(
      target: CoordinatorLeaseTarget(
        leaseId: lease.id,
        repoId: _requiredOwnership(lease.repoId, 'repository'),
        projectRoot: _requiredOwnership(lease.projectRoot, 'project root'),
      ),
      actor: _actor,
    );
  }

  @override
  void close() => _gateway.close();

  static CoordinatorContainerTarget _containerTarget(
    CoordinatorContainer container,
  ) {
    return CoordinatorContainerTarget(
      resourceId: container.id,
      repoId: _requiredOwnership(container.repoId, 'repository'),
      projectRoot: _requiredOwnership(container.projectRoot, 'project root'),
      name: container.name,
      containerId: container.containerId,
    );
  }

  static String _requiredOwnership(String? value, String label) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      throw StateError(
        'This resource has no canonical $label ownership and cannot be '
        'mutated safely.',
      );
    }
    return normalized;
  }
}
