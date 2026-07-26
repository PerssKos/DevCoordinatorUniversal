import 'package:coordinator_client/coordinator_client.dart';
import 'package:release_update/release_update.dart';

import '../core/storage/settings_store.dart';

abstract interface class AppCoordinatorService {
  bool supports(CoordinatorCapability capability);

  Future<CoordinatorInventory> loadInventory();

  Future<CoordinatorActionResult> actOnServer(
    CoordinatorServer server,
    CoordinatorResourceAction action,
  );

  Future<CoordinatorActionResult> actOnProject(
    CoordinatorProject project,
    CoordinatorProjectAction action,
  );

  Future<CoordinatorActionResult> actOnContainer(
    CoordinatorContainer container,
    CoordinatorResourceAction action,
  );

  Future<CoordinatorLogResult> readServerLogs(
    CoordinatorServer server, {
    int tail = 200,
  });

  Future<CoordinatorLogResult> readContainerLogs(
    CoordinatorContainer container, {
    int tail = 200,
  });

  Future<CoordinatorLease> leasePort({
    required CoordinatorProject project,
    required CoordinatorServer server,
    required int firstPort,
    required int lastPort,
    int? preferredPort,
    Duration? ttl,
    String? purpose,
  });

  Future<CoordinatorActionResult> releasePort(CoordinatorLease lease);

  void close();
}

abstract interface class AppCoordinatorServiceFactory {
  Future<AppCoordinatorService> connect({
    required StoredConnectionProfile profile,
    String? credential,
    bool interactive = false,
    void Function(CoordinatorConnectionProgress progress)? onProgress,
  });
}

enum CoordinatorConnectionProgress {
  validatingEndpoint,
  refreshingSession,
  launchingBrowser,
  awaitingCallback,
  exchangingCode,
}

abstract interface class NativeStoredSessionRevoker {
  /// Revokes a securely stored native session when no live adapter exists.
  ///
  /// Failure must retain a potentially live refresh credential so revocation
  /// can be retried. Once its revocation-pending fence is durably stored, that
  /// credential is eligible only for retry and never for reconnect.
  Future<void> revokeStoredNativeSession(StoredConnectionProfile profile);
}

final class NativeActionGate {
  const NativeActionGate.allowed() : allowed = true, reason = null;

  const NativeActionGate.blocked(this.reason) : allowed = false;

  final bool allowed;
  final String? reason;
}

/// Native-v2 application adapter that preserves immutable gateway identities.
///
/// It deliberately exposes native DTOs rather than filling legacy path,
/// launch-argument, or Docker-ID fields with invented values.
abstract interface class NativeAppCoordinatorService
    implements AppCoordinatorService {
  NativeGatewayMeta get nativeMeta;

  NativeGatewaySession get nativeSession;

  NativeGatewayInventory? get currentNativeInventory;

  NativeGatewayEntityTag? get currentNativeEntityTag;

  Future<NativeGatewayInventory> loadNativeInventory();

  NativeActionGate canActOnNativeProject(
    NativeGatewayProject project,
    NativeGatewayResourceAction action,
  );

  NativeActionGate canActOnNativeResource(
    NativeGatewayResource resource,
    NativeGatewayResourceAction action,
  );

  NativeActionGate canReadNativeLogs(NativeGatewayResource resource);

  NativeActionGate canManageNativeLease({
    required String projectId,
    String? leaseId,
  });

  Future<NativeGatewayOperation> actOnNativeProject(
    NativeGatewayProject project,
    NativeGatewayResourceAction action, {
    String? reason,
  });

  Future<NativeGatewayOperation> actOnNativeResource(
    NativeGatewayResource resource,
    NativeGatewayResourceAction action, {
    String? reason,
  });

  Future<NativeGatewayLogPage> readNativeLogs(
    NativeGatewayResource resource, {
    String? cursor,
    int limit = 200,
  });

  Future<NativeGatewayPortLease> leaseNativePort({
    required NativeGatewayProject project,
    required NativeGatewayResource server,
    required int firstPort,
    required int lastPort,
    required String purpose,
    int? preferredPort,
    Duration? ttl,
  });

  Future<void> releaseNativePort(NativeGatewayPortLease lease);

  Future<NativeGatewayEventPage> loadNativeEvents({
    String? after,
    int limit = 100,
  });

  Future<void> revokeNativeSession();
}

final class AppUpdateResult {
  const AppUpdateResult({
    this.release,
    this.message,
    this.checkedAt,
    this.releaseCache,
    this.updateSuppression,
  });

  final ReleaseInfo? release;
  final String? message;
  final DateTime? checkedAt;
  final Map<String, Object?>? releaseCache;
  final Map<String, Object?>? updateSuppression;
}

abstract interface class AppUpdateService {
  Future<AppUpdateResult> check({
    required String currentVersion,
    required bool manual,
    DateTime? lastCheckedAt,
    Map<String, Object?>? releaseCache,
    Map<String, Object?>? updateSuppression,
  });

  Map<String, Object?> ignore({
    required ReleaseInfo release,
    Map<String, Object?>? currentSuppression,
  });

  Map<String, Object?> remindLater({
    required ReleaseInfo release,
    Map<String, Object?>? currentSuppression,
  });

  /// Opens a validated HTTPS update destination outside the app.
  ///
  /// This future completes only after the platform launcher accepts the
  /// destination. Implementations throw when validation or launch fails.
  Future<void> openRelease(ReleaseInfo release);
}
