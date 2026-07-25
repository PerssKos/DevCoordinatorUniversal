import 'package:coordinator_client/coordinator_client.dart';

/// The narrow lifecycle controls that the legacy inventory can justify.
///
/// Native v2 uses its server-authored `allowedActions` and blockers instead.
enum LegacyServerControlPolicy { startOnly, restartAndStop, blocked }

LegacyServerControlPolicy legacyServerControlPolicy(CoordinatorServer server) {
  final status = _normalizedState(server.status);
  final health = _normalizedState(server.healthClassification);

  if (status == 'stopped') {
    final healthAgrees =
        health.isEmpty || health == 'stopped' || health == 'not_running';
    if (healthAgrees && server.healthOk != true) {
      return LegacyServerControlPolicy.startOnly;
    }
    return LegacyServerControlPolicy.blocked;
  }

  if (status == 'running') {
    final healthAllowsRecovery =
        health.isEmpty || health == 'healthy' || health == 'unhealthy';
    final healthIsConsistent =
        !(health == 'healthy' && server.healthOk == false);
    if (healthAllowsRecovery && healthIsConsistent) {
      return LegacyServerControlPolicy.restartAndStop;
    }
    return LegacyServerControlPolicy.blocked;
  }

  if (status == 'unhealthy') {
    final healthAllowsRecovery = health.isEmpty || health == 'unhealthy';
    if (healthAllowsRecovery && server.healthOk != true) {
      return LegacyServerControlPolicy.restartAndStop;
    }
  }

  return LegacyServerControlPolicy.blocked;
}

bool isLeaseReleasable(CoordinatorLease lease, {required DateTime now}) {
  final status = _normalizedState(lease.status);
  if (status != 'active' && status != 'expiring') {
    return false;
  }
  final expiresAt = lease.expiresAt;
  return expiresAt == null || expiresAt.toUtc().isAfter(now.toUtc());
}

String _normalizedState(String? value) =>
    (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
