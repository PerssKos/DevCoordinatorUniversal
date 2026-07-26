import 'dart:async';

import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator/app/app_services.dart';
import 'package:devcoordinator/core/storage/secure_token_store.dart';
import 'package:devcoordinator/core/storage/settings_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:release_update/release_update.dart';

final class FakeSettingsStore implements AppSettingsStore {
  FakeSettingsStore(this.value, {this.events});

  PersistedAppSettings value;
  final List<String>? events;
  Object? readError;
  Object? writeError;
  Object? cleanupMarkerError;
  final List<Object?> queuedWriteErrors = <Object?>[];
  final List<Object?> queuedCleanupMarkerErrors = <Object?>[];
  int readCount = 0;
  final List<PersistedAppSettings> writes = <PersistedAppSettings>[];
  final List<bool> cleanupMarkers = <bool>[];

  @override
  Future<PersistedAppSettings> read() async {
    readCount += 1;
    events?.add('settings.read');
    final error = readError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<void> write(PersistedAppSettings settings) async {
    events?.add('settings.write');
    final error = queuedWriteErrors.isEmpty
        ? writeError
        : queuedWriteErrors.removeAt(0);
    if (error != null) throw error;
    value = settings.copyWith(
      credentialCleanupPending: value.credentialCleanupPending,
    );
    writes.add(value);
  }

  @override
  Future<void> setCredentialCleanupPending(bool pending) async {
    events?.add('settings.cleanupMarker.$pending');
    final error = queuedCleanupMarkerErrors.isEmpty
        ? cleanupMarkerError
        : queuedCleanupMarkerErrors.removeAt(0);
    if (error != null) throw error;
    cleanupMarkers.add(pending);
    value = value.copyWith(credentialCleanupPending: pending);
  }
}

final class FakeTokenStore implements SecureTokenStore {
  FakeTokenStore({this.value, this.persistedLegacyValue, this.events});

  /// Process-session value returned by [read].
  String? value;

  /// Old durable value that current production code may delete but never read.
  String? persistedLegacyValue;
  final List<String>? events;
  Object? readError;
  Object? writeError;
  Object? clearError;
  final List<Object?> queuedClearErrors = <Object?>[];
  int readCount = 0;
  int purgeLegacyCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<String?> read() async {
    readCount += 1;
    events?.add('token.read');
    final error = readError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<void> purgeLegacyValue() async {
    purgeLegacyCount += 1;
    events?.add('token.purgeLegacy');
    final cleanupError = _nextClearError();
    if (cleanupError != null) {
      throw cleanupError;
    }
    persistedLegacyValue = null;
  }

  @override
  Future<void> write(String token) async {
    writeCount += 1;
    events?.add('token.write');
    final error = writeError;
    if (error != null) throw error;
    final cleanupError = _nextClearError();
    if (cleanupError != null) throw cleanupError;
    persistedLegacyValue = null;
    value = token;
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    events?.add('token.clear');
    value = null;
    final error = _nextClearError();
    if (error != null) throw error;
    persistedLegacyValue = null;
  }

  Object? _nextClearError() {
    return queuedClearErrors.isEmpty
        ? clearError
        : queuedClearErrors.removeAt(0);
  }
}

final class ConnectionAttempt {
  const ConnectionAttempt({
    required this.profile,
    required this.credential,
    required this.interactive,
  });

  final StoredConnectionProfile profile;
  final String? credential;
  final bool interactive;
}

final class FakeCoordinatorServiceFactory
    implements AppCoordinatorServiceFactory {
  FakeCoordinatorServiceFactory({required this.service, this.events});

  final FakeCoordinatorService service;
  final List<String>? events;
  Object? connectError;
  final List<ConnectionAttempt> attempts = <ConnectionAttempt>[];

  @override
  Future<AppCoordinatorService> connect({
    required StoredConnectionProfile profile,
    String? credential,
    bool interactive = false,
    void Function(CoordinatorConnectionProgress progress)? onProgress,
  }) async {
    events?.add('factory.connect');
    attempts.add(
      ConnectionAttempt(
        profile: profile,
        credential: credential,
        interactive: interactive,
      ),
    );
    final error = connectError;
    if (error != null) throw error;
    return service;
  }
}

final class LeaseCall {
  const LeaseCall({
    required this.project,
    required this.server,
    required this.firstPort,
    required this.lastPort,
    required this.preferredPort,
    required this.ttl,
    required this.purpose,
  });

  final CoordinatorProject project;
  final CoordinatorServer server;
  final int firstPort;
  final int lastPort;
  final int? preferredPort;
  final Duration? ttl;
  final String? purpose;
}

final class FakeCoordinatorService implements AppCoordinatorService {
  FakeCoordinatorService({
    CoordinatorInventory? inventory,
    List<CoordinatorInventory>? inventories,
    Iterable<CoordinatorCapability>? capabilities,
    this.events,
  }) : inventories =
           inventories ?? <CoordinatorInventory>[inventory ?? emptyInventory()],
       capabilities = Set<CoordinatorCapability>.unmodifiable(
         capabilities ?? CoordinatorCapability.values,
       );

  final List<String>? events;
  final List<CoordinatorInventory> inventories;
  final Set<CoordinatorCapability> capabilities;
  Object? inventoryError;
  Object? leaseError;
  Object? releaseError;
  Object? serverActionError;
  Object? projectActionError;
  Object? containerActionError;
  Completer<void>? projectActionGate;
  CoordinatorLease leaseResponse = leaseFixture();
  CoordinatorActionResult actionResponse = CoordinatorActionResult(
    data: const <String, Object?>{'ok': true},
    ok: true,
    status: 'completed',
  );
  CoordinatorLogResult logResponse = const CoordinatorLogResult(
    text: 'log',
    truncated: false,
  );
  int loadCount = 0;
  int closeCount = 0;
  final List<LeaseCall> leaseCalls = <LeaseCall>[];
  final List<CoordinatorLease> releaseCalls = <CoordinatorLease>[];
  final List<(CoordinatorServer, CoordinatorResourceAction)> serverActions =
      <(CoordinatorServer, CoordinatorResourceAction)>[];
  final List<(CoordinatorProject, CoordinatorProjectAction)> projectActions =
      <(CoordinatorProject, CoordinatorProjectAction)>[];
  final List<(CoordinatorContainer, CoordinatorResourceAction)>
  containerActions = <(CoordinatorContainer, CoordinatorResourceAction)>[];
  final List<CoordinatorServer> serverLogCalls = <CoordinatorServer>[];
  final List<CoordinatorContainer> containerLogCalls = <CoordinatorContainer>[];

  @override
  bool supports(CoordinatorCapability capability) =>
      capabilities.contains(capability);

  @override
  Future<CoordinatorInventory> loadInventory() async {
    loadCount += 1;
    events?.add('service.loadInventory');
    final error = inventoryError;
    if (error != null) throw error;
    final index = loadCount - 1;
    return inventories[index < inventories.length
        ? index
        : inventories.length - 1];
  }

  @override
  Future<CoordinatorActionResult> actOnServer(
    CoordinatorServer server,
    CoordinatorResourceAction action,
  ) async {
    serverActions.add((server, action));
    final error = serverActionError;
    if (error != null) throw error;
    return actionResponse;
  }

  @override
  Future<CoordinatorActionResult> actOnProject(
    CoordinatorProject project,
    CoordinatorProjectAction action,
  ) async {
    projectActions.add((project, action));
    final gate = projectActionGate;
    if (gate != null) await gate.future;
    final error = projectActionError;
    if (error != null) throw error;
    return actionResponse;
  }

  @override
  Future<CoordinatorActionResult> actOnContainer(
    CoordinatorContainer container,
    CoordinatorResourceAction action,
  ) async {
    containerActions.add((container, action));
    final error = containerActionError;
    if (error != null) throw error;
    return actionResponse;
  }

  @override
  Future<CoordinatorLogResult> readServerLogs(
    CoordinatorServer server, {
    int tail = 200,
  }) async {
    serverLogCalls.add(server);
    return logResponse;
  }

  @override
  Future<CoordinatorLogResult> readContainerLogs(
    CoordinatorContainer container, {
    int tail = 200,
  }) async {
    containerLogCalls.add(container);
    return logResponse;
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
  }) async {
    leaseCalls.add(
      LeaseCall(
        project: project,
        server: server,
        firstPort: firstPort,
        lastPort: lastPort,
        preferredPort: preferredPort,
        ttl: ttl,
        purpose: purpose,
      ),
    );
    final error = leaseError;
    if (error != null) throw error;
    return leaseResponse;
  }

  @override
  Future<CoordinatorActionResult> releasePort(CoordinatorLease lease) async {
    releaseCalls.add(lease);
    final error = releaseError;
    if (error != null) throw error;
    return actionResponse;
  }

  @override
  void close() {
    closeCount += 1;
    events?.add('service.close');
  }
}

final class UpdateCheckCall {
  const UpdateCheckCall({
    required this.currentVersion,
    required this.manual,
    this.lastCheckedAt,
    this.releaseCache,
    this.updateSuppression,
  });

  final String currentVersion;
  final bool manual;
  final DateTime? lastCheckedAt;
  final Map<String, Object?>? releaseCache;
  final Map<String, Object?>? updateSuppression;
}

final class FakeUpdateService implements AppUpdateService {
  AppUpdateResult result = const AppUpdateResult();
  Object? checkError;
  Object? openError;
  final List<Object?> queuedOpenErrors = <Object?>[];
  Map<String, Object?> ignoreResult = <String, Object?>{
    'ignoredThroughVersion': '2.0.0',
    'deferredThroughVersion': null,
    'deferredUntil': null,
  };
  Map<String, Object?> remindLaterResult = <String, Object?>{
    'ignoredThroughVersion': null,
    'deferredThroughVersion': '2.0.0',
    'deferredUntil': '2030-01-02T00:00:00.000Z',
  };
  final List<UpdateCheckCall> checks = <UpdateCheckCall>[];
  final List<ReleaseInfo> ignored = <ReleaseInfo>[];
  final List<ReleaseInfo> deferred = <ReleaseInfo>[];
  final List<ReleaseInfo> openAttempts = <ReleaseInfo>[];
  final List<ReleaseInfo> opened = <ReleaseInfo>[];

  @override
  Future<AppUpdateResult> check({
    required String currentVersion,
    required bool manual,
    DateTime? lastCheckedAt,
    Map<String, Object?>? releaseCache,
    Map<String, Object?>? updateSuppression,
  }) async {
    checks.add(
      UpdateCheckCall(
        currentVersion: currentVersion,
        manual: manual,
        lastCheckedAt: lastCheckedAt,
        releaseCache: releaseCache,
        updateSuppression: updateSuppression,
      ),
    );
    final error = checkError;
    if (error != null) throw error;
    return result;
  }

  @override
  Map<String, Object?> ignore({
    required ReleaseInfo release,
    Map<String, Object?>? currentSuppression,
  }) {
    ignored.add(release);
    return ignoreResult;
  }

  @override
  Map<String, Object?> remindLater({
    required ReleaseInfo release,
    Map<String, Object?>? currentSuppression,
  }) {
    deferred.add(release);
    return remindLaterResult;
  }

  @override
  Future<void> openRelease(ReleaseInfo release) async {
    openAttempts.add(release);
    final error = queuedOpenErrors.isEmpty
        ? openError
        : queuedOpenErrors.removeAt(0);
    if (error != null) throw error;
    opened.add(release);
  }
}

StoredConnectionProfile localProfile({
  String label = 'Workstation',
  String baseUrl = 'http://127.0.0.1:29876',
}) {
  return StoredConnectionProfile(
    kind: StoredConnectionKind.localLegacyV1,
    baseUrl: baseUrl,
    label: label,
    agent: 'test-app',
  );
}

CoordinatorProject projectFixture({
  String id = 'repo-1',
  String root = '/work/repo-1',
  String displayName = 'Project One',
  bool startupFenced = false,
}) {
  return CoordinatorProject(
    id: id,
    canonicalRoot: root,
    displayName: displayName,
    installationStatus: 'verified',
    startupFenced: startupFenced,
  );
}

CoordinatorServer enrolledServerFixture({
  String id = 'server-1',
  String repoId = 'repo-1',
  String projectRoot = '/work/repo-1',
  String name = 'Server One',
  String status = 'stopped',
  List<String> arguments = const <String>['serve'],
  int? port,
  String? healthClassification,
  bool? healthOk,
}) {
  return CoordinatorServer(
    id: id,
    repoId: repoId,
    projectRoot: projectRoot,
    name: name,
    status: status,
    arguments: arguments,
    port: port,
    healthClassification: healthClassification,
    healthOk: healthOk,
  );
}

CoordinatorLease leaseFixture({
  String id = 'lease-1',
  int port = 3210,
  String status = 'active',
  String? repoId = 'repo-1',
  String? projectRoot = '/work/repo-1',
  DateTime? expiresAt,
}) {
  return CoordinatorLease(
    id: id,
    port: port,
    status: status,
    repoId: repoId,
    projectRoot: projectRoot,
    purpose: 'integration test',
    expiresAt: expiresAt,
  );
}

CoordinatorInventory emptyInventory({
  List<CoordinatorProject> projects = const <CoordinatorProject>[],
  List<CoordinatorServer> servers = const <CoordinatorServer>[],
  List<CoordinatorContainer> containers = const <CoordinatorContainer>[],
  List<CoordinatorLease> leases = const <CoordinatorLease>[],
  List<CoordinatorEvent> events = const <CoordinatorEvent>[],
}) {
  return CoordinatorInventory(
    schemaVersion: 1,
    source: CoordinatorInventorySource.normalized,
    projects: projects,
    servers: servers,
    containers: containers,
    leases: leases,
    events: events,
    backups: const <CoordinatorBackup>[],
    unassignedResources: const <CoordinatorUnassignedResource>[],
  );
}

ReleaseInfo releaseFixture({String version = '2.0.0'}) {
  return ReleaseInfo(
    id: 20,
    version: Version.parse(version),
    tagName: 'v$version',
    pageUri: Uri.parse(
      'https://github.com/example/devcoordinator/releases/tag/v$version',
    ),
    publishedAt: DateTime.utc(2030, 1, 1),
    name: 'DevCoordinator $version',
    notes: 'Signed release notes.',
  );
}

Future<PackageInfo> packageInfoFixture({String version = '1.0.0'}) async {
  return PackageInfo(
    appName: 'DevCoordinator',
    packageName: 'io.github.example.devcoordinator',
    version: version,
    buildNumber: '1',
  );
}
