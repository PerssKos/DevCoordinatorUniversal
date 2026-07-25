import 'dart:convert';

import 'package:coordinator_client/coordinator_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late List<http.Request> requests;
  late LegacyLoopbackV1Client client;
  late CoordinatorActor actor;
  late CoordinatorProjectTarget project;
  late CoordinatorServerTarget server;
  late CoordinatorContainerTarget container;

  setUp(() {
    requests = [];
    client = LegacyLoopbackV1Client(
      endpoint: CoordinatorEndpoint.legacyV1(
        Uri.parse('http://localhost:29876'),
      ),
      tokenProvider: CallbackCoordinatorTokenProvider(
        () async => 'fixture-token',
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path == '/healthz') {
          return jsonResponse({
            'ok': true,
            'service': 'codex-dev-coordinator',
            'version': '0.1.0-test',
          });
        }
        if (path == '/v1/inventory') {
          return jsonResponse(normalizedInventoryFixture());
        }
        if (path == '/v1/events') {
          return jsonResponse({
            'events': [
              {
                'event_id': 'event-2',
                'event_kind': 'server.lifecycle',
                'occurred_at': '2026-07-25T12:00:00Z',
              },
            ],
            'next_cursor': 'cursor-2',
            'has_more': false,
          });
        }
        if (path.endsWith('/logs')) {
          return path.contains('/docker/')
              ? jsonResponse({
                  'stdout': 'docker output',
                  'stderr': '',
                  'returncode': 0,
                })
              : jsonResponse({'text': 'server output', 'truncated': false});
        }
        if (path == '/v1/ports/lease') {
          return jsonResponse({
            'id': 'lease-new',
            'project': '/srv/project',
            'port': 3350,
            'status': 'active',
            'purpose': 'preview',
          });
        }
        if (path == '/v1/archives') {
          return jsonResponse({
            'archives': [
              {
                'target_kind': 'repository',
                'target_id': 'repo-1',
                'display_name': 'Project',
                'restorable': true,
                'removable': true,
                'effects': ['fence starts'],
                'retained': ['history'],
                'blockers': [],
              },
            ],
          });
        }
        if (path == '/v1/lifecycle/plan') {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return jsonResponse({
            'plan_id': 'plan-1',
            'plan_fingerprint': 'sha256:plan',
            'target_kind': body['target_kind'],
            'target_id': body['target_id'],
            'action': body['action'],
            'effects': ['stop exact resource'],
            'retained': ['history'],
            'deleted': [],
            'blockers': [],
            'confirmation_phrase': body['action'] == 'purge'
                ? 'PURGE project repo-1'
                : '',
          });
        }
        return jsonResponse({
          'ok': true,
          'status': 'completed',
          'partial': false,
          'needs_attention': false,
        });
      }),
    );
    actor = CoordinatorActor('operator@example.test');
    project = CoordinatorProjectTarget(
      repoId: 'repo-1',
      canonicalRoot: '/srv/project',
    );
    server = CoordinatorServerTarget(
      id: 'server-1',
      repoId: 'repo-1',
      projectRoot: '/srv/project',
      name: 'web',
    );
    container = CoordinatorContainerTarget(
      resourceId: 'docker-resource-1',
      repoId: 'repo-1',
      projectRoot: '/srv/project',
      name: 'postgres',
      containerId:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  });

  Map<String, Object?> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, Object?>;

  test(
    'legacy meta verifies identity before returning static capabilities',
    () async {
      final meta = await client.readMeta();
      expect(meta.apiMajor, 1);
      expect(meta.serverVersion, '0.1.0-test');
      expect(meta.supports(CoordinatorCapability.durableLifecycle), isTrue);
      expect(meta.supports(CoordinatorCapability.containerLifecycle), isFalse);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/healthz');
      expect(requests.single.followRedirects, isFalse);
      expect(requests.single.headers, isNot(contains('authorization')));
    },
  );

  test(
    'inventory and events use exact read endpoints and opaque cursors',
    () async {
      final inventory = await client.readInventory();
      final page = await client.readEvents(after: 'opaque value/+', limit: 250);

      expect(inventory.projects.single.id, 'repo-1');
      expect(page.events.single.id, 'event-2');
      expect(requests[0].url.path, '/v1/inventory');
      expect(requests[1].url.path, '/v1/events');
      expect(requests[1].url.queryParameters['after'], 'opaque value/+');
      expect(requests[1].url.queryParameters['limit'], '250');
      expect(() => client.readEvents(limit: 501), throwsArgumentError);
    },
  );

  test('server start keeps argv boundaries and exact lease binding', () async {
    await client.startServer(
      CoordinatorServerStartRequest(
        target: CoordinatorServerLaunchTarget(
          repoId: 'repo-1',
          projectRoot: '/srv/project',
          name: 'preview',
        ),
        actor: actor,
        arguments: ['dart', 'run', '--define=value with spaces'],
        range: CoordinatorPortRange(3300, 3399),
        preferredPort: 3350,
        cwd: '/srv/project',
        healthUrl: 'http://127.0.0.1:{port}/healthz',
        leaseId: 'lease-manual',
      ),
    );

    expect(requests.single.url.path, '/v1/servers/start');
    expect(bodyOf(requests.single), {
      'agent': 'operator@example.test',
      'project': '/srv/project',
      'name': 'preview',
      'argv': ['dart', 'run', '--define=value with spaces'],
      'range': '3300-3399',
      'cwd': '/srv/project',
      'preferred': 3350,
      'health_url': 'http://127.0.0.1:{port}/healthz',
      'lease_id': 'lease-manual',
    });
  });

  test('server stop and restart serialize the exact target identity', () async {
    for (final action in [
      CoordinatorResourceAction.stop,
      CoordinatorResourceAction.restart,
    ]) {
      await client.actOnServer(
        target: server,
        actor: actor,
        action: action,
        reason: '  update  ',
      );
    }
    final logs = await client.readServerLogs(server, tail: 321);

    for (final (index, action) in [
      CoordinatorResourceAction.stop,
      CoordinatorResourceAction.restart,
    ].indexed) {
      expect(requests[index].url.path, '/v1/servers/${action.name}');
      expect(bodyOf(requests[index]), {
        'server_id': 'server-1',
        'agent': 'operator@example.test',
        'project': '/srv/project',
        'name': 'web',
        'reason': 'update',
      });
    }
    expect(bodyOf(requests[2]), {
      'server_id': 'server-1',
      'project': '/srv/project',
      'name': 'web',
      'tail': 321,
    });
    expect(logs.text, 'server output');
    expect(
      () => client.actOnServer(
        target: server,
        actor: actor,
        action: CoordinatorResourceAction.start,
      ),
      throwsArgumentError,
    );
  });

  test('project actions retain attribution', () async {
    await client.actOnProject(
      target: project,
      actor: actor,
      action: CoordinatorProjectAction.stop,
    );

    expect(requests.single.url.path, '/v1/projects/stop');
    expect(bodyOf(requests.single), {
      'project': '/srv/project',
      'agent': 'operator@example.test',
    });
  });

  test('legacy container mutations fail closed before HTTP', () async {
    for (final action in CoordinatorResourceAction.values) {
      await expectLater(
        client.actOnContainer(target: container, actor: actor, action: action),
        throwsA(isA<CoordinatorCapabilityException>()),
      );
    }

    expect(requests, isEmpty);
  });

  test('container logs remain a read-only legacy operation', () async {
    final logs = await client.readContainerLogs(container, tail: 80);

    expect(requests.single.url.path, '/v1/docker/logs');
    expect(bodyOf(requests.single), {
      'container':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'tail': 80,
    });
    expect(logs.text, 'docker output');
    expect(logs.exitCode, 0);
  });

  test('container logs retain stderr-only and both output streams', () async {
    Future<CoordinatorLogResult> readLogs(Map<String, Object?> response) {
      final streamClient = LegacyLoopbackV1Client(
        endpoint: CoordinatorEndpoint.legacyV1(
          Uri.parse('http://localhost:29876'),
        ),
        tokenProvider: CallbackCoordinatorTokenProvider(
          () async => 'fixture-token',
        ),
        httpClient: MockClient((_) async => jsonResponse(response)),
      );
      addTearDown(streamClient.close);
      return streamClient.readContainerLogs(container);
    }

    final stderrOnly = await readLogs({
      'stdout': '',
      'stderr': 'container output on stderr\n',
      'returncode': 0,
    });
    expect(stderrOnly.text, 'container output on stderr\n');
    expect(stderrOnly.stderr, 'container output on stderr\n');

    final both = await readLogs({
      'stdout': 'standard output',
      'stderr': 'standard error',
      'returncode': 0,
    });
    expect(both.text, '[stdout]\nstandard output\n[stderr]\nstandard error');
    expect(both.stdout, 'standard output');
    expect(both.stderr, 'standard error');
  });

  test('container logs fail closed without an exact immutable ID', () async {
    final missingId = CoordinatorContainerTarget(
      resourceId: 'docker-resource-1',
      repoId: 'repo-1',
      projectRoot: '/srv/project',
      name: 'postgres',
    );
    final nameMasqueradingAsId = CoordinatorContainerTarget(
      resourceId: 'docker-resource-1',
      repoId: 'repo-1',
      projectRoot: '/srv/project',
      name: 'postgres',
      containerId: 'postgres',
    );

    await expectLater(
      client.readContainerLogs(missingId),
      throwsA(isA<CoordinatorCapabilityException>()),
    );
    await expectLater(
      client.readContainerLogs(nameMasqueradingAsId),
      throwsA(isA<CoordinatorCapabilityException>()),
    );
    expect(requests, isEmpty);
  });

  test('port lease/release/assign/unassign are exact and bounded', () async {
    final lease = await client.leasePort(
      CoordinatorPortLeaseRequest(
        project: project,
        server: server,
        actor: actor,
        range: CoordinatorPortRange(3300, 3399),
        preferredPort: 3350,
        ttl: const Duration(minutes: 30),
        purpose: 'preview',
      ),
    );
    await client.releasePort(
      target: CoordinatorLeaseTarget(
        leaseId: lease.id,
        repoId: 'repo-1',
        projectRoot: '/srv/project',
      ),
      actor: actor,
    );
    final assignment = CoordinatorPortAssignmentTarget(
      repoId: 'repo-1',
      projectRoot: '/srv/project',
      serverName: 'web',
    );
    await client.assignPort(target: assignment, actor: actor, port: 3310);
    await client.unassignPort(target: assignment, actor: actor);

    expect(lease.id, 'lease-new');
    expect(bodyOf(requests[0]), {
      'agent': 'operator@example.test',
      'project': '/srv/project',
      'name': 'web',
      'range': '3300-3399',
      'preferred': 3350,
      'ttl': 1800,
      'purpose': 'preview',
    });
    expect(bodyOf(requests[1])['lease_id'], 'lease-new');
    expect(bodyOf(requests[2])['port'], 3310);
    expect(bodyOf(requests[3]), {
      'agent': 'operator@example.test',
      'project': '/srv/project',
      'name': 'web',
    });
  });

  test('lifecycle methods bind plan identity and explicit restore', () async {
    final archives = await client.readArchives();
    final target = CoordinatorLifecycleTarget(
      kind: CoordinatorLifecycleTargetKind.project,
      id: 'repo-1',
    );
    final plan = await client.planLifecycle(
      target: target,
      action: CoordinatorLifecyclePlanAction.purge,
      actor: actor,
      reason: ' Remove old project ',
    );
    await client.applyLifecycle(
      CoordinatorLifecycleApply(
        planId: plan.id,
        planFingerprint: plan.fingerprint,
        confirmationPhrase: plan.confirmationPhrase!,
      ),
    );
    await client.restoreLifecycle(
      target: target,
      actor: actor,
      reason: 'restore definition',
    );

    expect(archives.single.target.kind, CoordinatorLifecycleTargetKind.project);
    expect(plan.blockers, isEmpty);
    expect(bodyOf(requests[1]), {
      'target_kind': 'project',
      'target_id': 'repo-1',
      'action': 'purge',
      'reason': 'Remove old project',
    });
    expect(bodyOf(requests[2]), {
      'plan_id': 'plan-1',
      'plan_fingerprint': 'sha256:plan',
      'confirmation_phrase': 'PURGE project repo-1',
    });
    expect(bodyOf(requests[3]), {
      'target_kind': 'project',
      'target_id': 'repo-1',
      'reason': 'restore definition',
    });
  });

  test('lifecycle reason is required before any HTTP dispatch', () async {
    final target = CoordinatorLifecycleTarget(
      kind: CoordinatorLifecycleTargetKind.project,
      id: 'repo-1',
    );

    await expectLater(
      client.planLifecycle(
        target: target,
        action: CoordinatorLifecyclePlanAction.archive,
        actor: actor,
        reason: '  ',
      ),
      throwsArgumentError,
    );
    expect(
      () => client.restoreLifecycle(target: target, actor: actor, reason: '\n'),
      throwsArgumentError,
    );
    expect(requests, isEmpty);
  });

  group('typed target validation', () {
    test('rejects empty identities, invalid ranges, ports, tails, and TTL', () {
      expect(() => CoordinatorActor(' '), throwsArgumentError);
      expect(
        () => CoordinatorProjectTarget(repoId: '', canonicalRoot: '/srv'),
        throwsArgumentError,
      );
      expect(() => CoordinatorPortRange(0, 10), throwsArgumentError);
      expect(() => CoordinatorPortRange(20, 10), throwsArgumentError);
      expect(
        () => CoordinatorPortLeaseRequest(
          project: project,
          server: server,
          actor: actor,
          range: CoordinatorPortRange(3300, 3310),
          preferredPort: 4000,
        ),
        throwsArgumentError,
      );
      expect(
        () => CoordinatorPortLeaseRequest(
          project: project,
          server: CoordinatorServerTarget(
            id: 'server-other',
            repoId: 'repo-other',
            projectRoot: '/srv/other',
            name: 'web',
          ),
          actor: actor,
          range: CoordinatorPortRange(3300, 3310),
        ),
        throwsArgumentError,
      );
      expect(
        () => CoordinatorServerStartRequest(
          target: CoordinatorServerLaunchTarget(
            repoId: 'repo-1',
            projectRoot: '/srv/project',
            name: 'web',
          ),
          actor: actor,
          arguments: [],
          range: CoordinatorPortRange(3300, 3310),
        ),
        throwsArgumentError,
      );
    });

    test('request methods reject invalid scalar bounds before HTTP', () async {
      expect(
        () => client.assignPort(
          target: CoordinatorPortAssignmentTarget(
            repoId: 'repo-1',
            projectRoot: '/srv/project',
            serverName: 'web',
          ),
          actor: actor,
          port: 70000,
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.readServerLogs(server, tail: 0),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
    });
  });
}
