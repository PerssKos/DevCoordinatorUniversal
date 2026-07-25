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
    required String credential,
  });
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
