import 'dart:async';
import 'dart:convert';

import 'package:coordinator_client/coordinator_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

NativeGatewayV2CoreClient makeNativeClient(
  MockClient httpClient, {
  Future<String?> Function()? token,
  NativeGatewayV2Limits limits = const NativeGatewayV2Limits(),
}) => NativeGatewayV2CoreClient(
  endpoint: CoordinatorEndpoint.nativeV2(
    Uri.parse('https://gateway.example.test/api/v2'),
  ),
  accessTokenProvider: CallbackNativeGatewayAccessTokenProvider(
    token ?? () async => 'access-token',
  ),
  httpClient: httpClient,
  limits: limits,
);

http.Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
  String contentType = 'application/json',
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': contentType, ...headers},
);

Map<String, Object?> metaFixture({
  List<String> capabilities = const [
    'inventory.read',
    'events.read',
    'resources.act',
  ],
}) => {
  'contractVersion': '2.0',
  'serverVersion': '2.4.1',
  'minimumClientVersion': '0.1.0',
  'capabilities': capabilities,
};

Map<String, Object?> sessionFixture() => {
  'userId': 'user-1',
  'email': 'operator@example.test',
  'displayName': 'Operator',
  'deviceSessionId': 'device-session-1',
  'roles': ['invited_operator'],
  'scopes': ['inventory:read', 'resources:act'],
  'grants': [
    {
      'resourceId': 'resource-1',
      'permissions': ['read', 'act'],
    },
  ],
  'expiresAt': '2026-07-25T13:00:00Z',
};

Map<String, Object?> inventoryFixture({bool partial = false}) => {
  'revision': 'revision-42',
  'observedAt': '2026-07-25T12:00:00Z',
  'partial': partial,
  'projects': [
    {
      'id': 'project-1',
      'displayName': 'Project',
      'state': 'running',
      'allowedActions': ['stop', 'restart'],
    },
  ],
  'resources': [
    {
      'id': 'resource-1',
      'projectId': 'project-1',
      'kind': 'server',
      'displayName': 'API',
      'state': 'running',
      'port': 3300,
      'cpuPercent': 5.25,
      'memoryBytes': 4096,
      'allowedActions': ['stop', 'restart'],
      'blockers': <Object?>[],
    },
  ],
  'leases': [
    {
      'id': 'lease-1',
      'projectId': 'project-1',
      'port': 3300,
      'purpose': 'API',
      'expiresAt': '2026-07-25T13:00:00Z',
    },
  ],
  'blockers': <Object?>[],
};

const operationId = '123e4567-e89b-42d3-a456-426614174000';

Map<String, Object?> operationFixture({
  String status = 'succeeded',
  bool partial = false,
  bool needsAttention = false,
  String targetStatus = 'succeeded',
  List<Object?> errors = const [],
}) => {
  'id': operationId,
  'status': status,
  'partial': partial,
  'needsAttention': needsAttention,
  'startedAt': '2026-07-25T12:00:00Z',
  'finishedAt': status == 'queued' || status == 'running'
      ? null
      : '2026-07-25T12:00:01Z',
  'resultRevision': status == 'succeeded' ? 'revision-43' : null,
  'results': [
    {
      'targetId': 'resource-1',
      'targetKind': 'server',
      'status': targetStatus,
      'message': 'Completed',
      'evidenceIds': ['event-1'],
    },
  ],
  'errors': errors,
};

void main() {
  group('public meta and authenticated session', () {
    test(
      'meta omits auth and ignores only unknown capability values',
      () async {
        var tokenReads = 0;
        late http.Request captured;
        final client = makeNativeClient(
          MockClient((request) async {
            captured = request;
            return jsonResponse(
              metaFixture(
                capabilities: const [
                  'inventory.read',
                  'resources.act',
                  'resources.action',
                  'future.profile',
                ],
              ),
              headers: {'etag': '"meta-1"'},
            );
          }),
          token: () async {
            tokenReads += 1;
            throw StateError('meta must not read credentials');
          },
        );

        final document = await client.readMeta();

        expect(captured.url.path, '/api/v2/meta');
        expect(captured.headers, isNot(contains('authorization')));
        expect(captured.followRedirects, isFalse);
        expect(captured.maxRedirects, 0);
        expect(tokenReads, 0);
        expect(document.entityTag?.value, '"meta-1"');
        expect(document.value.capabilities.values, {
          NativeGatewayCapability.inventoryRead,
          NativeGatewayCapability.resourcesAct,
        });
      },
    );

    test(
      'session obtains a fresh bearer for its authenticated request',
      () async {
        var tokenReads = 0;
        late http.Request captured;
        final client = makeNativeClient(
          MockClient((request) async {
            captured = request;
            return jsonResponse(sessionFixture());
          }),
          token: () async {
            tokenReads += 1;
            return 'session-access-token';
          },
        );

        final session = await client.readSession();

        expect(tokenReads, 1);
        expect(captured.url.path, '/api/v2/session');
        expect(
          captured.headers['authorization'],
          'Bearer session-access-token',
        );
        expect(session.roles, {NativeGatewaySessionRole.invitedOperator});
        expect(session.hasScope('resources:act'), isTrue);
        expect(session.hasPermission('resource-1', 'act'), isTrue);
      },
    );

    test('missing access token fails before HTTP dispatch', () async {
      var requests = 0;
      final client = makeNativeClient(
        MockClient((_) async {
          requests += 1;
          return jsonResponse(sessionFixture());
        }),
        token: () async => ' token with spaces ',
      );

      await expectLater(
        client.readSession(),
        throwsA(isA<CoordinatorAuthenticationException>()),
      );
      expect(requests, 0);
    });
  });

  group('ETag inventory cache contract', () {
    test('returns a typed snapshot then honors 304 If-None-Match', () async {
      final requests = <http.Request>[];
      final client = makeNativeClient(
        MockClient((request) async {
          requests.add(request);
          if (requests.length == 1) {
            return jsonResponse(
              inventoryFixture(),
              headers: {'etag': '"inventory-42"'},
            );
          }
          return http.Response('', 304);
        }),
      );

      final first = await client.readInventory();
      expect(first, isA<NativeGatewayModified<NativeGatewayInventory>>());
      final modified = first as NativeGatewayModified<NativeGatewayInventory>;
      expect(modified.value.resources.single.id, 'resource-1');
      expect(modified.entityTag.value, '"inventory-42"');

      final second = await client.readInventory(
        ifNoneMatch: modified.entityTag,
      );
      expect(second, isA<NativeGatewayNotModified<NativeGatewayInventory>>());
      expect(requests[0].headers, isNot(contains('if-none-match')));
      expect(requests[1].headers['if-none-match'], '"inventory-42"');
    });

    test('requires a strong ETag on a fresh inventory response', () async {
      for (final headers in <Map<String, String>>[
        const {},
        const {'etag': 'W/"inventory-42"'},
      ]) {
        final client = makeNativeClient(
          MockClient(
            (_) async => jsonResponse(inventoryFixture(), headers: headers),
          ),
        );
        await expectLater(
          client.readInventory(),
          throwsA(isA<CoordinatorProtocolException>()),
        );
      }
    });

    test('fails closed instead of exposing a partial inventory', () async {
      final client = makeNativeClient(
        MockClient(
          (_) async => jsonResponse(
            inventoryFixture(partial: true),
            headers: {'etag': '"partial-1"'},
          ),
        ),
      );

      await expectLater(
        client.readInventory(),
        throwsA(isA<CoordinatorSemanticException>()),
      );
    });
  });

  group('RFC 9457 failures and credential safety', () {
    test('parses problem details and redacts the active bearer', () async {
      const credential = 'private-native-token';
      final client = makeNativeClient(
        MockClient(
          (_) async => jsonResponse(
            {
              'type': 'https://gateway.example.test/problems/forbidden',
              'title': 'Forbidden',
              'status': 403,
              'detail': 'Bearer $credential cannot access this resource',
              'code': 'grant_missing',
              'requestId': 'request-1',
              'blockers': [
                {
                  'code': 'grant_missing',
                  'message': 'Grant required',
                  'recovery': null,
                },
              ],
              'access_token': credential,
              'client_secret': 'different-private-value',
            },
            status: 403,
            contentType: 'application/problem+json',
          ),
        ),
        token: () async => credential,
      );

      try {
        await client.readSession();
        fail('Expected an RFC 9457 failure.');
      } on NativeGatewayProblemException catch (error) {
        expect(error.httpStatus, 403);
        expect(error.problem.status, 403);
        expect(error.problem.code, 'grant_missing');
        expect(error.problem.blockers.single.code, 'grant_missing');
        expect(error.problem.detail, contains('[redacted]'));
        expect(error.problem.extensions['access_token'], '[redacted]');
        expect(error.problem.extensions['client_secret'], '[redacted]');
        expect(error.toString(), isNot(contains(credential)));
      }
    });

    test('does not expose an untyped non-problem error body', () async {
      const secret = 'server-secret-value';
      final client = makeNativeClient(
        MockClient((_) async => jsonResponse({'error': secret}, status: 500)),
      );

      await expectLater(
        client.readSession(),
        throwsA(
          isA<CoordinatorHttpException>()
              .having((error) => error.response, 'raw response', isNull)
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains(secret)),
              ),
        ),
      );
    });
  });

  group('typed core endpoints and mutation headers', () {
    test('resource action binds exact target, revision, and UUID', () async {
      late http.Request captured;
      final client = makeNativeClient(
        MockClient((request) async {
          captured = request;
          return jsonResponse(operationFixture(), status: 202);
        }),
      );
      final revision = NativeGatewayEntityTag.parse('"revision-42"');
      final key = NativeGatewayIdempotencyKey.parse(
        'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      );

      final operation = await client.actOnResource(
        resourceId: 'server/blue',
        action: NativeGatewayResourceAction.restart,
        request: NativeGatewayActionRequest(reason: 'Deploy complete'),
        ifMatch: revision,
        idempotencyKey: key,
      );

      expect(
        captured.url.toString(),
        'https://gateway.example.test/api/v2/resources/server%2Fblue/actions/restart',
      );
      expect(captured.url.pathSegments[3], 'server/blue');
      expect(captured.headers['if-match'], '"revision-42"');
      expect(
        captured.headers['idempotency-key'],
        'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      );
      expect(captured.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(captured.body), {'reason': 'Deploy complete'});
      expect(operation.isTerminal, isTrue);
      expect(operation.isSuccessful, isTrue);
      expect(operation.resultRevision, 'revision-43');
    });

    test(
      'port lease creation and exact release use contract methods',
      () async {
        final requests = <http.Request>[];
        final client = makeNativeClient(
          MockClient((request) async {
            requests.add(request);
            if (request.method == 'POST') {
              return jsonResponse({
                'id': 'lease/one',
                'projectId': 'project-1',
                'port': 3350,
                'purpose': 'preview',
                'expiresAt': '2026-07-25T13:00:00Z',
              }, status: 201);
            }
            return http.Response('', 204);
          }),
        );
        final revision = NativeGatewayEntityTag.parse('"revision-42"');
        final createKey = NativeGatewayIdempotencyKey.parse(
          '11111111-2222-4333-8444-555555555555',
        );
        final releaseKey = NativeGatewayIdempotencyKey.parse(
          '66666666-7777-4888-8999-aaaaaaaaaaaa',
        );

        final lease = await client.createPortLease(
          request: NativeGatewayLeaseRequest(
            projectId: 'project-1',
            purpose: 'preview',
            preferredPort: 3350,
            ttlSeconds: 1800,
          ),
          ifMatch: revision,
          idempotencyKey: createKey,
        );
        await client.releasePortLease(
          leaseId: lease.id,
          ifMatch: revision,
          idempotencyKey: releaseKey,
        );

        expect(requests[0].method, 'POST');
        expect(requests[0].url.path, '/api/v2/ports/leases');
        expect(requests[0].headers['if-match'], '"revision-42"');
        expect(requests[1].method, 'DELETE');
        expect(
          requests[1].url.toString(),
          'https://gateway.example.test/api/v2/ports/leases/lease%2Fone',
        );
        expect(requests[1].url.pathSegments.last, 'lease/one');
        expect(requests[1].headers['idempotency-key'], releaseKey.value);
      },
    );

    test('lifecycle plan and apply retain server-authored binding', () async {
      final requests = <http.Request>[];
      final client = makeNativeClient(
        MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/v2/lifecycle/plans') {
            return jsonResponse({
              'id': 'plan/one',
              'fingerprint': 'sha256:plan',
              'targetId': 'project-1',
              'action': 'purge',
              'effects': ['stop exact resources'],
              'retained': ['audit history'],
              'deleted': ['working tree'],
              'blockers': <Object?>[],
              'confirmationPhrase': 'PURGE Project',
              'expiresAt': '2026-07-25T12:05:00Z',
            }, status: 201);
          }
          return jsonResponse(operationFixture(status: 'queued'), status: 202);
        }),
      );
      final revision = NativeGatewayEntityTag.parse('"revision-42"');
      final planKey = NativeGatewayIdempotencyKey.parse(
        '10000000-0000-4000-8000-000000000001',
      );
      final applyKey = NativeGatewayIdempotencyKey.parse(
        '10000000-0000-4000-8000-000000000002',
      );

      final plan = await client.createLifecyclePlan(
        request: NativeGatewayLifecyclePlanRequest(
          targetKind: NativeGatewayLifecycleTargetKind.project,
          targetId: 'project-1',
          action: NativeGatewayLifecycleAction.purge,
          reason: 'Project retired',
        ),
        ifMatch: revision,
        idempotencyKey: planKey,
      );
      final operation = await client.applyLifecyclePlan(
        planId: plan.id,
        request: NativeGatewayLifecycleApplyRequest(
          planFingerprint: plan.fingerprint,
          confirmationPhrase: plan.confirmationPhrase,
        ),
        idempotencyKey: applyKey,
      );

      expect(requests[0].headers['if-match'], '"revision-42"');
      expect(
        requests[1].url.toString(),
        'https://gateway.example.test/api/v2/lifecycle/plans/plan%2Fone/apply',
      );
      expect(jsonDecode(requests[1].body), {
        'planFingerprint': 'sha256:plan',
        'confirmationPhrase': 'PURGE Project',
      });
      expect(operation.status, NativeGatewayOperationStatus.queued);
      expect(operation.isTerminal, isFalse);
      expect(operation.isSuccessful, isFalse);
    });

    test(
      'events, logs, operation polling, and revocation use fixed paths',
      () async {
        final requests = <http.Request>[];
        final client = makeNativeClient(
          MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/events')) {
              return jsonResponse({
                'events': [
                  {
                    'id': 'event-1',
                    'projectId': 'project-1',
                    'resourceId': 'resource-1',
                    'kind': 'resource.lifecycle',
                    'code': 'stopped',
                    'message': 'Stopped',
                    'occurredAt': '2026-07-25T12:00:00Z',
                  },
                ],
                'nextCursor': 'cursor-2',
                'hasMore': true,
              });
            }
            if (request.url.path.endsWith('/logs')) {
              return jsonResponse({
                'lines': ['line 1', 'line 2'],
                'nextCursor': null,
                'truncated': false,
              });
            }
            if (request.url.path.contains('/operations/')) {
              return jsonResponse(operationFixture());
            }
            return http.Response('', 204);
          }),
        );

        final events = await client.readEvents(after: 'cursor + /', limit: 250);
        final logs = await client.readResourceLogs(
          resourceId: 'resource-1',
          cursor: 'opaque + /',
          limit: 500,
        );
        final operation = await client.readOperation(operationId);
        await client.revokeCurrentSession();

        expect(events.events.single.id, 'event-1');
        expect(requests[0].url.queryParameters['after'], 'cursor + /');
        expect(logs.lines, ['line 1', 'line 2']);
        expect(requests[1].url.queryParameters['cursor'], 'opaque + /');
        expect(requests[2].url.path, '/api/v2/operations/$operationId');
        expect(operation.isSuccessful, isTrue);
        expect(requests[3].method, 'DELETE');
        expect(requests[3].url.path, '/api/v2/session');
      },
    );
  });

  group('unknown mutation outcomes', () {
    test('a dispatched mutation timeout is explicitly inconclusive', () async {
      const privateReason = 'private mutation body';
      final client = makeNativeClient(
        MockClient((_) async {
          await Completer<void>().future;
          return jsonResponse(operationFixture(), status: 202);
        }),
        token: () async => 'private-access-token',
        limits: const NativeGatewayV2Limits(
          requestTimeout: Duration(milliseconds: 10),
        ),
      );

      try {
        await client.actOnResource(
          resourceId: 'resource-1',
          action: NativeGatewayResourceAction.stop,
          request: NativeGatewayActionRequest(reason: privateReason),
          ifMatch: NativeGatewayEntityTag.parse('"revision-42"'),
          idempotencyKey: NativeGatewayIdempotencyKey.parse(
            'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          ),
        );
        fail('Expected an unknown outcome.');
      } on CoordinatorMutationOutcomeUnknownException catch (error) {
        expect(error.method, 'POST');
        expect(error.path, '/resources/{resourceId}/actions/stop');
        expect(error.timeout, const Duration(milliseconds: 10));
        expect(error.toString(), isNot(contains(privateReason)));
        expect(error.toString(), isNot(contains('private-access-token')));
      }
    });

    test('a dispatched mutation transport break is inconclusive', () async {
      const credential = 'private-transport-token';
      final client = makeNativeClient(
        MockClient(
          (_) async => throw http.ClientException(
            'socket failed while using $credential',
          ),
        ),
        token: () async => credential,
      );

      await expectLater(
        client.releasePortLease(
          leaseId: 'lease-1',
          ifMatch: NativeGatewayEntityTag.parse('"revision-42"'),
          idempotencyKey: NativeGatewayIdempotencyKey.parse(
            'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          ),
        ),
        throwsA(
          isA<CoordinatorMutationOutcomeUnknownException>().having(
            (error) => error.toString(),
            'credential-safe text',
            isNot(contains(credential)),
          ),
        ),
      );
    });

    test('a malformed accepted 202 operation is inconclusive', () async {
      final client = makeNativeClient(
        MockClient(
          (_) async => jsonResponse({
            'id': operationId,
            'status': 'queued',
          }, status: 202),
        ),
      );

      await expectLater(
        client.actOnResource(
          resourceId: 'resource-1',
          action: NativeGatewayResourceAction.stop,
          request: NativeGatewayActionRequest(reason: 'maintenance'),
          ifMatch: NativeGatewayEntityTag.parse('"revision-42"'),
          idempotencyKey: NativeGatewayIdempotencyKey.parse(
            'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          ),
        ),
        throwsA(
          isA<CoordinatorMutationOutcomeUnknownException>()
              .having((error) => error.method, 'method', 'POST')
              .having(
                (error) => error.path,
                'path',
                '/resources/{resourceId}/actions/stop',
              ),
        ),
      );
    });

    test('a malformed accepted 201 lease is inconclusive', () async {
      final client = makeNativeClient(
        MockClient(
          (_) async => jsonResponse({
            'id': 'lease-1',
            'projectId': 'project-1',
          }, status: 201),
        ),
      );

      await expectLater(
        client.createPortLease(
          request: NativeGatewayLeaseRequest(
            projectId: 'project-1',
            purpose: 'preview',
          ),
          ifMatch: NativeGatewayEntityTag.parse('"revision-42"'),
          idempotencyKey: NativeGatewayIdempotencyKey.parse(
            '11111111-2222-4333-8444-555555555555',
          ),
        ),
        throwsA(
          isA<CoordinatorMutationOutcomeUnknownException>()
              .having((error) => error.method, 'method', 'POST')
              .having((error) => error.path, 'path', '/ports/leases'),
        ),
      );
    });

    test('a non-2xx mutation problem remains determinate', () async {
      final client = makeNativeClient(
        MockClient(
          (_) async => jsonResponse(
            {
              'type': 'https://gateway.example.test/problems/conflict',
              'title': 'Conflict',
              'status': 409,
              'detail': 'The reviewed revision is stale.',
            },
            status: 409,
            contentType: 'application/problem+json',
          ),
        ),
      );

      await expectLater(
        client.actOnResource(
          resourceId: 'resource-1',
          action: NativeGatewayResourceAction.stop,
          request: NativeGatewayActionRequest(reason: 'maintenance'),
          ifMatch: NativeGatewayEntityTag.parse('"revision-42"'),
          idempotencyKey: NativeGatewayIdempotencyKey.parse(
            'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          ),
        ),
        throwsA(
          isA<NativeGatewayProblemException>()
              .having((error) => error.httpStatus, 'HTTP status', 409)
              .having((error) => error.problem.status, 'problem status', 409),
        ),
      );
    });

    test('a pre-dispatch mutation deadline prevents a late send', () async {
      var requests = 0;
      final client = makeNativeClient(
        MockClient((_) async {
          requests += 1;
          return http.Response('', 204);
        }),
        token: () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return 'access-token';
        },
        limits: const NativeGatewayV2Limits(
          requestTimeout: Duration(milliseconds: 5),
        ),
      );

      await expectLater(
        client.releasePortLease(
          leaseId: 'lease-1',
          ifMatch: NativeGatewayEntityTag.parse('"revision-42"'),
          idempotencyKey: NativeGatewayIdempotencyKey.parse(
            'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          ),
        ),
        throwsA(isA<CoordinatorTimeoutException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(requests, 0);
    });

    test('an authenticated read timeout remains an ordinary timeout', () async {
      final client = makeNativeClient(
        MockClient((_) async {
          await Completer<void>().future;
          return jsonResponse(sessionFixture());
        }),
        limits: const NativeGatewayV2Limits(
          requestTimeout: Duration(milliseconds: 10),
        ),
      );

      await expectLater(
        client.readSession(),
        throwsA(isA<CoordinatorTimeoutException>()),
      );
    });
  });

  group('strict schemas and unsafe input rejection', () {
    test('rejects additional fields, duplicates, and closed-enum drift', () {
      const parser = NativeGatewayV2Parser();

      expect(
        () => parser.parseMeta({...metaFixture(), 'unexpected': true}),
        throwsA(isA<CoordinatorProtocolException>()),
      );
      expect(
        () => parser.parseMeta(
          metaFixture(capabilities: const ['inventory.read', 'inventory.read']),
        ),
        throwsA(isA<CoordinatorProtocolException>()),
      );
      expect(
        () => parser.parseSession({
          ...sessionFixture(),
          'roles': ['future_owner'],
        }),
        throwsA(isA<CoordinatorProtocolException>()),
      );
      expect(
        () => parser.parseOperation({
          ...operationFixture(),
          'status': 'completed',
        }),
        throwsA(isA<CoordinatorProtocolException>()),
      );
      expect(
        () => parser.parseInventory({...inventoryFixture(), 'partial': 0}),
        throwsA(isA<CoordinatorProtocolException>()),
      );
    });

    test('operation success is semantic, not just a status label', () {
      const parser = NativeGatewayV2Parser();
      final failedTarget = parser.parseOperation(
        operationFixture(targetStatus: 'failed'),
      );
      final needsAttention = parser.parseOperation(
        operationFixture(needsAttention: true),
      );
      final partial = parser.parseOperation(operationFixture(partial: true));

      expect(failedTarget.isSuccessful, isFalse);
      expect(needsAttention.isSuccessful, isFalse);
      expect(partial.isSuccessful, isFalse);
    });

    test(
      'rejects unsafe revisions, UUIDs, fields, and request sizes',
      () async {
        expect(
          () => NativeGatewayEntityTag.parse('W/"revision"'),
          throwsArgumentError,
        );
        expect(
          () => NativeGatewayEntityTag.parse('"revision"\r\nInjected: true'),
          throwsArgumentError,
        );
        expect(
          () => NativeGatewayIdempotencyKey.parse('not-a-uuid'),
          throwsArgumentError,
        );
        expect(
          () => NativeGatewayActionRequest(reason: 'x' * 301),
          throwsArgumentError,
        );
        expect(
          () => NativeGatewayActionRequest(reason: 'ok\r\nunsafe'),
          throwsArgumentError,
        );
        expect(
          () => NativeGatewayLeaseRequest(
            projectId: 'project-1',
            purpose: 'preview',
            ttlSeconds: 59,
          ),
          throwsArgumentError,
        );

        var requests = 0;
        final client = makeNativeClient(
          MockClient((_) async {
            requests += 1;
            return jsonResponse(operationFixture(), status: 202);
          }),
          limits: const NativeGatewayV2Limits(maxRequestBytes: 4),
        );
        await expectLater(
          client.actOnResource(
            resourceId: 'resource-1',
            action: NativeGatewayResourceAction.stop,
            request: NativeGatewayActionRequest(reason: 'bounded'),
            ifMatch: NativeGatewayEntityTag.parse('"revision-42"'),
            idempotencyKey: NativeGatewayIdempotencyKey.parse(
              'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
            ),
          ),
          throwsA(isA<CoordinatorBodyTooLargeException>()),
        );
        expect(requests, 0);
      },
    );

    test(
      'rejects wrong success content type and oversized responses',
      () async {
        final wrongType = makeNativeClient(
          MockClient(
            (_) async =>
                jsonResponse(sessionFixture(), contentType: 'text/plain'),
          ),
        );
        await expectLater(
          wrongType.readSession(),
          throwsA(isA<CoordinatorProtocolException>()),
        );

        final oversized = makeNativeClient(
          MockClient((_) async => jsonResponse(sessionFixture())),
          limits: const NativeGatewayV2Limits(maxResponseBytes: 10),
        );
        await expectLater(
          oversized.readSession(),
          throwsA(isA<CoordinatorBodyTooLargeException>()),
        );
      },
    );
  });
}
