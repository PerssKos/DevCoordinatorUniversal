import 'package:coordinator_client/coordinator_client.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  const parser = CoordinatorInventoryParser();

  group('normalized inventory', () {
    test(
      'joins exact normalized identities and compatibility presentation',
      () {
        final inventory = parser.parse(normalizedInventoryFixture());

        expect(inventory.schemaVersion, 2);
        expect(inventory.source, CoordinatorInventorySource.normalized);
        expect(inventory.stateRevision, 8);
        expect(inventory.observationRevision, 13);
        expect(inventory.projects.single.id, 'repo-1');

        final server = inventory.servers.single;
        expect(server.id, 'server-1');
        expect(server.repoId, 'repo-1');
        expect(server.projectRoot, '/srv/project');
        expect(server.status, 'running');
        expect(server.pid, 4321);
        expect(server.port, 3310);
        expect(server.url, 'http://127.0.0.1:3310');
        expect(server.leaseId, 'lease-1');
        expect(server.healthOk, isTrue);
        expect(server.usage?.cpuPercent, 12.5);

        final container = inventory.containers.single;
        expect(container.id, 'docker-resource-1');
        expect(container.repoId, 'repo-1');
        expect(container.projectRoot, '/srv/project');
        expect(container.status, 'running');
        expect(container.ports.single.hostPort, 5432);
        expect(container.usage?.memoryBytes, 4096);

        expect(inventory.leases.single.id, 'lease-1');
        expect(inventory.events.single.id, 'event-1');
        expect(inventory.backups.single.id, 'backup-1');
        expect(inventory.unassignedResources.single.canAttach, isTrue);
      },
    );

    test('does not infer a project from ambiguous container membership', () {
      final fixture = normalizedInventoryFixture();
      (fixture['memberships']! as List<Object?>).add({
        'membership_id': 'membership-2',
        'repo_id': 'repo-2',
        'resource_kind': 'container',
        'host_resource_id': 'docker-resource-1',
        'immutable_fingerprint': 'sha256:other',
      });
      (fixture['repositories']! as List<Object?>).add({
        'repo_id': 'repo-2',
        'canonical_root': '/srv/other',
        'display_name': 'Other',
      });

      final inventory = parser.parse(fixture);
      expect(inventory.containers.single.repoId, isNull);
      expect(inventory.containers.single.projectRoot, isNull);
    });

    test('retains the committed lease port for a stopped server', () {
      final fixture = normalizedInventoryFixture();
      final observations =
          (fixture['observations']! as Map<String, Object?>)['servers']!
              as List<Object?>;
      (observations.single as Map).remove('listener_port');

      final inventory = parser.parse(fixture);

      expect(inventory.servers.single.port, 3310);
      expect(inventory.servers.single.leaseId, 'lease-1');
    });
  });

  test('parses the explicit v1 compatibility projection', () {
    final inventory = parser.parse(compatibilityInventoryFixture());

    expect(inventory.source, CoordinatorInventorySource.compatibility);
    expect(inventory.projects.single.canonicalRoot, '/srv/legacy');
    expect(inventory.servers.single.id, 'legacy-server');
    expect(inventory.containers.single.id, 'legacy-container');
    expect(inventory.containers.single.usage?.memoryBytes, 512);
    expect(inventory.leases.single.id, 'legacy-lease');
    expect(inventory.events.single.kind, 'server.stop');
    expect(inventory.backups.single.databaseName, 'app');
    expect(inventory.unassignedResources.single.reasonCode, 'missing_repo');
  });

  group('strict parsing', () {
    test('rejects non-object roots and unsupported schemas', () {
      expect(
        () => parser.parse([]),
        throwsA(isA<CoordinatorProtocolException>()),
      );
      expect(
        () => parser.parse({'schema_version': 99}),
        throwsA(isA<CoordinatorProtocolException>()),
      );
    });

    test('rejects wrong field types and malformed timestamps', () {
      final badType = normalizedInventoryFixture();
      badType['repositories'] = 'not-an-array';
      expect(
        () => parser.parse(badType),
        throwsA(isA<CoordinatorProtocolException>()),
      );

      final badDate = normalizedInventoryFixture();
      final events = badDate['events']! as List<Object?>;
      (events.single as Map<String, Object?>)['occurred_at'] = 'not-a-date';
      expect(
        () => parser.parse(badDate),
        throwsA(isA<CoordinatorProtocolException>()),
      );
    });

    test('rejects duplicate immutable identities', () {
      final fixture = normalizedInventoryFixture();
      final servers =
          (fixture['resources']! as Map<String, Object?>)['servers']!
              as List<Object?>;
      servers.add(servers.single);
      expect(
        () => parser.parse(fixture),
        throwsA(isA<CoordinatorProtocolException>()),
      );
    });

    test('rejects duplicate repository-scoped server wire targets', () {
      final fixture = normalizedInventoryFixture();
      final servers =
          (fixture['resources']! as Map<String, Object?>)['servers']!
              as List<Object?>;
      final duplicateName = Map<String, Object>.from(
        servers.single! as Map<String, Object>,
      )..['server_definition_id'] = 'server-2';
      servers.add(duplicateName);

      expect(
        () => parser.parse(fixture),
        throwsA(isA<CoordinatorProtocolException>()),
      );
    });
  });

  test('parses opaque event pagination without interpreting the cursor', () {
    final page = parser.parseEventPage({
      'events': [
        {
          'event_id': 'event-2',
          'repo_id': 'repo-1',
          'event_kind': 'docker.lifecycle',
          'occurred_at': '2026-07-25T12:01:00Z',
        },
      ],
      'next_cursor': 'opaque::cursor/value',
      'has_more': true,
    });
    expect(page.events.single.id, 'event-2');
    expect(page.nextCursor, 'opaque::cursor/value');
    expect(page.hasMore, isTrue);
  });
}
