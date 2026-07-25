import 'dart:convert';

import 'package:http/http.dart' as http;

Map<String, Object?> normalizedInventoryFixture() => {
  'schema_version': 2,
  'store': {
    'state_revision': 8,
    'observation_revision': 13,
    'updated_at': '2026-07-25T12:00:00Z',
  },
  'repositories': [
    {
      'repo_id': 'repo-1',
      'canonical_root': '/srv/project',
      'display_name': 'Project',
      'installation_status': 'active',
      'startup_fenced': false,
    },
  ],
  'memberships': [
    {
      'membership_id': 'membership-1',
      'repo_id': 'repo-1',
      'resource_kind': 'container',
      'host_resource_id': 'docker-resource-1',
      'immutable_fingerprint': 'sha256:membership',
    },
  ],
  'resources': {
    'servers': [
      {
        'server_definition_id': 'server-1',
        'repo_id': 'repo-1',
        'name': 'web',
        'role': 'web',
        'cwd': '/srv/project',
        'arguments': ['dart', 'run'],
        'health_url_template': 'http://127.0.0.1:{port}/healthz',
        'log_path': '/tmp/web.log',
      },
    ],
    'docker': [
      {
        'docker_resource_id': 'docker-resource-1',
        'engine_id': 'engine-1',
        'full_container_id':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'current_name': 'postgres',
        'image': 'postgres:16',
        'created_at': '2026-07-25T10:00:00Z',
        'updated_at': '2026-07-25T11:59:00Z',
      },
    ],
    'docker_ports': [
      {
        'docker_resource_id': 'docker-resource-1',
        'ordinal': 0,
        'host_address': '127.0.0.1',
        'host_port': 5432,
        'container_port': 5432,
        'protocol': 'tcp',
      },
    ],
    'databases': [],
  },
  'leases': [
    {
      'lease_id': 'lease-1',
      'repo_id': 'repo-1',
      'server_definition_id': 'server-1',
      'port': 3310,
      'status': 'active',
      'agent': 'fixture',
      'purpose': 'web',
      'owner': '123',
      'created_at': '2026-07-25T10:00:00Z',
      'expires_at': '2026-07-26T10:00:00Z',
    },
  ],
  'events': [
    {
      'event_id': 'event-1',
      'repo_id': 'repo-1',
      'source_id': 'source-1',
      'event_kind': 'server.lifecycle',
      'code': 'server_started',
      'message': 'web started',
      'occurred_at': '2026-07-25T11:58:00Z',
    },
  ],
  'database_backups': [
    {
      'database_backup_id': 'backup-1',
      'database_binding_id': 'database-1',
      'docker_resource_id': 'docker-resource-1',
      'repo_id': 'repo-1',
      'scope': 'database',
      'source_container_id':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'source_database_name': 'app',
      'artifact_path': '/private/app.dump',
      'artifact_size_bytes': 2048,
      'artifact_sha256': 'sha256:artifact',
      'manifest_path': '/private/app.manifest.json',
      'backup_format': 'custom',
      'verification_status': 'verified',
      'verification_mode': 'restore_test',
      'status': 'available',
      'created_at': '2026-07-25T09:00:00Z',
      'verified_at': '2026-07-25T09:05:00Z',
    },
  ],
  'unassigned_resources': [
    {
      'unassigned_id': 'unassigned-1',
      'resource_kind': 'container',
      'resource_id': 'docker-resource-2',
      'display_name': 'orphan',
      'reason_code': 'name_only',
      'explanation': 'Only a name was observed.',
      'observed_by': ['/home/user/.codex/agent-coordinator'],
      'controller': '/home/user/.codex/agent-coordinator',
      'immutable_fingerprint': 'sha256:immutable',
      'control_binding_id': 'binding-1',
      'ownership_fingerprint': 'sha256:ownership',
      'can_attach': true,
      'can_retire': true,
      'lifecycle_violation': false,
      'recommended_next_step': 'Choose a project.',
    },
  ],
  'observations': {
    'servers': [
      {
        'server_definition_id': 'server-1',
        'lifecycle': 'running',
        'pid': 4321,
        'listener_host': '127.0.0.1',
        'listener_port': 3310,
        'listener_observable': 1,
        'health_classification': 'healthy',
        'health_ok': 1,
        'sampled_at': '2026-07-25T11:59:00Z',
      },
    ],
    'docker': [
      {
        'docker_resource_id': 'docker-resource-1',
        'lifecycle': 'running',
        'health': 'healthy',
        'restart_policy': 'unless-stopped',
        'sampled_at': '2026-07-25T11:59:00Z',
      },
    ],
    'telemetry': [
      {
        'sample_id': 'sample-server',
        'host_resource_kind': 'server',
        'host_resource_id': 'server-1',
        'sampled_at': '2026-07-25T11:59:00Z',
        'cpu_percent': 12.5,
        'memory_bytes': 1024,
      },
      {
        'sample_id': 'sample-docker',
        'host_resource_kind': 'docker',
        'host_resource_id': 'docker-resource-1',
        'sampled_at': '2026-07-25T11:59:00Z',
        'cpu_percent': 4.25,
        'memory_bytes': 4096,
      },
    ],
    'snapshots': [],
  },
  'v1_compatibility': {
    'servers': [
      {
        'id': 'server-1',
        'name': 'web',
        'project': '/srv/project',
        'status': 'running',
        'url': 'http://127.0.0.1:3310',
        'lease_id': 'lease-1',
        'health': {'classification': 'healthy', 'ok': true},
      },
    ],
    'docker': {
      'available': true,
      'containers': [
        {
          'id':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'host_resource_id': 'docker-resource-1',
          'name': 'postgres',
          'project': '/srv/project',
          'status': 'running',
          'ports': '127.0.0.1:5432->5432/tcp',
        },
      ],
    },
    'leases': [],
    'recent_events': [],
    'backups': [],
    'project_usage': [],
  },
};

Map<String, Object?> compatibilityInventoryFixture() => {
  'schema_version': 1,
  'v1_compatibility': {
    'project_usage': [
      {
        'usage_key': 'path:/srv/legacy',
        'project': '/srv/legacy',
        'display_name': 'Legacy',
      },
    ],
    'servers': [
      {
        'id': 'legacy-server',
        'name': 'web',
        'project': '/srv/legacy',
        'cwd': '/srv/legacy',
        'argv': ['python3', 'server.py'],
        'status': 'stopped',
        'port': 3300,
        'health': {'classification': 'stopped', 'ok': false},
      },
    ],
    'docker': {
      'available': true,
      'containers': [
        {
          'id': 'bbbbbbbbbbbb',
          'host_resource_id': 'legacy-container',
          'name': 'redis',
          'project': '/srv/legacy',
          'image': 'redis:7',
          'status': 'running',
          'ports': '127.0.0.1:6379->6379/tcp',
          'stats': {
            'timestamp': '2026-07-25T12:00:00Z',
            'cpu_percent': 1.5,
            'memory_usage_bytes': 512,
          },
        },
      ],
    },
    'leases': [
      {
        'id': 'legacy-lease',
        'project': '/srv/legacy',
        'server_id': 'legacy-server',
        'port': 3300,
        'status': 'active',
        'expires_at': null,
      },
    ],
    'recent_events': [
      {
        'id': 'legacy-event',
        'type': 'server.stop',
        'message': 'stopped',
        'at': '2026-07-25T11:00:00Z',
        'project': '/srv/legacy',
      },
    ],
    'backups': [
      {
        'id': 'legacy-backup',
        'project': '/srv/legacy',
        'path': '/private/legacy.dump',
        'container_id': 'bbbbbbbbbbbb',
        'container': 'postgres',
        'database': 'app',
        'status': 'available',
        'verification_status': 'verified',
        'created_at': '2026-07-25T08:00:00Z',
      },
    ],
  },
  'unassigned_resources': [
    {
      'unassigned_id': 'legacy-unassigned',
      'resource_kind': 'server',
      'resource_id': 'unknown-server',
      'display_name': 'unknown',
      'reason_code': 'missing_repo',
      'observed_by': [],
      'can_attach': false,
      'can_retire': false,
      'lifecycle_violation': false,
    },
  ],
};

http.Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);
