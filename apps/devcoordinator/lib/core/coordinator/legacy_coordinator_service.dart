import 'package:coordinator_client/coordinator_client.dart';
import 'package:http/http.dart' as http;

import '../../app/app_services.dart';
import '../platform/platform_support.dart';
import '../storage/settings_store.dart';

/// Creates the only connection supported by the current server: its local,
/// loopback-only v1 API. Native v2 deliberately has no placeholder transport.
final class PlatformCoordinatorServiceFactory
    implements AppCoordinatorServiceFactory {
  PlatformCoordinatorServiceFactory({
    bool? supportsLegacyLocalConnection,
    http.Client Function()? clientFactory,
  }) : _supportsLegacyLocalConnection =
           supportsLegacyLocalConnection ??
           PlatformSupport.supportsLegacyLocalConnection,
       _clientFactory = clientFactory ?? http.Client.new;

  final bool _supportsLegacyLocalConnection;
  final http.Client Function() _clientFactory;

  @override
  Future<AppCoordinatorService> connect({
    required StoredConnectionProfile profile,
    required String credential,
  }) async {
    if (profile.kind == StoredConnectionKind.nativeGatewayV2) {
      throw UnsupportedError(
        'Native gateway v2 is not deployed. This client will not use the '
        'host-wide loopback token as a remote credential.',
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
    final normalizedCredential = credential.trim();
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
