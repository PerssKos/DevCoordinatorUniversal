import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator/core/coordinator/legacy_action_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('legacy server control policy', () {
    test('permits start only for a conclusively stopped server', () {
      expect(
        legacyServerControlPolicy(_server('stopped')),
        LegacyServerControlPolicy.startOnly,
      );
      expect(
        legacyServerControlPolicy(
          _server('stopped', healthClassification: 'stopped', healthOk: false),
        ),
        LegacyServerControlPolicy.startOnly,
      );
    });

    test('permits recovery controls for running and unhealthy servers', () {
      expect(
        legacyServerControlPolicy(
          _server('running', healthClassification: 'healthy', healthOk: true),
        ),
        LegacyServerControlPolicy.restartAndStop,
      );
      expect(
        legacyServerControlPolicy(
          _server(
            'unhealthy',
            healthClassification: 'unhealthy',
            healthOk: false,
          ),
        ),
        LegacyServerControlPolicy.restartAndStop,
      );
    });

    test('blocks transitional, unknown, failed, and identity-risk states', () {
      for (final status in <String>[
        'starting',
        'stopping',
        'unknown',
        'unobserved',
        'failed',
        'archived',
      ]) {
        expect(
          legacyServerControlPolicy(_server(status)),
          LegacyServerControlPolicy.blocked,
          reason: status,
        );
      }
      for (final health in <String>[
        'wrong-listener',
        'unverified_listener',
        'stop-outcome-uncertain',
        'starting',
        'stopping',
      ]) {
        expect(
          legacyServerControlPolicy(
            _server('running', healthClassification: health),
          ),
          LegacyServerControlPolicy.blocked,
          reason: health,
        );
      }
    });

    test('blocks internally contradictory lifecycle evidence', () {
      expect(
        legacyServerControlPolicy(
          _server('running', healthClassification: 'healthy', healthOk: false),
        ),
        LegacyServerControlPolicy.blocked,
      );
      expect(
        legacyServerControlPolicy(
          _server('stopped', healthClassification: 'stopped', healthOk: true),
        ),
        LegacyServerControlPolicy.blocked,
      );
    });
  });

  group('lease release policy', () {
    final now = DateTime.utc(2026, 7, 25, 12);

    test('permits active and expiring leases before their expiry', () {
      for (final status in <String>['active', 'expiring']) {
        expect(
          isLeaseReleasable(
            _lease(status, expiresAt: now.add(const Duration(minutes: 1))),
            now: now,
          ),
          isTrue,
          reason: status,
        );
      }
      expect(isLeaseReleasable(_lease('active'), now: now), isTrue);
    });

    test('blocks expired time and every retained or failed state', () {
      expect(
        isLeaseReleasable(_lease('active', expiresAt: now), now: now),
        isFalse,
      );
      for (final status in <String>[
        'expired',
        'released',
        'failed',
        'conflicted',
        'unknown',
      ]) {
        expect(
          isLeaseReleasable(_lease(status), now: now),
          isFalse,
          reason: status,
        );
      }
    });
  });
}

CoordinatorServer _server(
  String status, {
  String? healthClassification,
  bool? healthOk,
}) {
  return CoordinatorServer(
    id: 'server-1',
    repoId: 'repo-1',
    projectRoot: '/work/repo-1',
    name: 'Server One',
    status: status,
    arguments: const <String>['serve'],
    port: 3210,
    healthClassification: healthClassification,
    healthOk: healthOk,
  );
}

CoordinatorLease _lease(String status, {DateTime? expiresAt}) {
  return CoordinatorLease(
    id: 'lease-1',
    port: 3210,
    status: status,
    repoId: 'repo-1',
    projectRoot: '/work/repo-1',
    expiresAt: expiresAt,
  );
}
