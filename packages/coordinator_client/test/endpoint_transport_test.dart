import 'dart:async';
import 'dart:convert';

import 'package:coordinator_client/coordinator_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

LegacyLoopbackV1Client makeClient(
  MockClient mock, {
  Future<String?> Function()? token,
  CoordinatorClientLimits limits = const CoordinatorClientLimits(),
}) => LegacyLoopbackV1Client(
  endpoint: CoordinatorEndpoint.legacyV1(Uri.parse('http://127.0.0.42:29876')),
  tokenProvider: CallbackCoordinatorTokenProvider(
    token ?? () async => 'fixture-token',
  ),
  httpClient: mock,
  limits: limits,
);

void main() {
  group('endpoint policy', () {
    test('legacy accepts only localhost and literal 127/8', () {
      expect(
        CoordinatorEndpoint.legacyV1(Uri.parse('http://localhost:29876')).kind,
        CoordinatorConnectionKind.legacyLoopbackV1,
      );
      expect(
        CoordinatorEndpoint.legacyV1(
          Uri.parse('https://127.255.10.9:443'),
        ).uri.host,
        '127.255.10.9',
      );

      for (final uri in [
        'http://example.com:29876',
        'http://10.0.0.1:29876',
        'http://[::1]:29876',
        'ftp://127.0.0.1',
        'http://127.0.0.1/base',
        'http://user:secret@127.0.0.1',
        'http://127.0.0.1?token=secret',
      ]) {
        expect(
          () => CoordinatorEndpoint.legacyV1(Uri.parse(uri)),
          throwsA(isA<CoordinatorEndpointException>()),
          reason: uri,
        );
      }
    });

    test('native v2 is HTTPS-only and preserves an explicit base path', () {
      final endpoint = CoordinatorEndpoint.nativeV2(
        Uri.parse('https://gateway.example.test/api'),
      );
      expect(endpoint.kind, CoordinatorConnectionKind.nativeGatewayV2);
      expect(
        endpoint.resolve('/meta').toString(),
        'https://gateway.example.test/api/meta',
      );
      expect(
        () => CoordinatorEndpoint.nativeV2(
          Uri.parse('http://gateway.example.test'),
        ),
        throwsA(isA<CoordinatorEndpointException>()),
      );
    });

    test('legacy client refuses a native endpoint', () {
      expect(
        () => LegacyLoopbackV1Client(
          endpoint: CoordinatorEndpoint.nativeV2(
            Uri.parse('https://gateway.example.test'),
          ),
          tokenProvider: CallbackCoordinatorTokenProvider(() async => 'token'),
          httpClient: MockClient((_) async => jsonResponse({})),
        ),
        throwsA(isA<CoordinatorEndpointException>()),
      );
    });
  });

  group('authentication and request boundary', () {
    test(
      'public identity preflight rejects a wrong listener before token access',
      () async {
        var tokenReads = 0;
        late http.Request captured;
        final client = makeClient(
          MockClient((request) async {
            captured = request;
            return jsonResponse({
              'ok': true,
              'service': 'another-development-server',
              'version': '1.0.0',
            });
          }),
          token: () async {
            tokenReads += 1;
            return 'must-not-be-read';
          },
        );

        await expectLater(
          client.readMeta(),
          throwsA(isA<CoordinatorProtocolException>()),
        );
        expect(tokenReads, 0);
        expect(captured.url.path, '/healthz');
        expect(captured.followRedirects, isFalse);
        expect(captured.headers, isNot(contains('authorization')));
      },
    );

    test('public identity preflight fails closed on redirects', () async {
      var tokenReads = 0;
      var requests = 0;
      final client = makeClient(
        MockClient((request) async {
          requests += 1;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'http://127.0.0.1:39999/collect'},
          );
        }),
        token: () async {
          tokenReads += 1;
          return 'must-not-be-read';
        },
      );

      await expectLater(
        client.readMeta(),
        throwsA(isA<CoordinatorProtocolException>()),
      );
      expect(requests, 1);
      expect(tokenReads, 0);
    });

    test(
      'reads the token asynchronously and sends it only as Bearer auth',
      () async {
        var reads = 0;
        late http.Request captured;
        final client = makeClient(
          MockClient((request) async {
            captured = request;
            return jsonResponse(normalizedInventoryFixture());
          }),
          token: () async {
            reads += 1;
            return 'injected-token';
          },
        );

        await client.readInventory();
        expect(reads, 1);
        expect(captured.headers['authorization'], 'Bearer injected-token');
        expect(captured.url.query, isEmpty);
        expect(captured.headers['accept'], 'application/json');
        expect(captured.followRedirects, isFalse);
      },
    );

    test(
      'missing, malformed, and failing providers fail before HTTP',
      () async {
        var requests = 0;
        final mock = MockClient((_) async {
          requests += 1;
          return jsonResponse({});
        });
        for (final provider in <Future<String?> Function()>[
          () async => null,
          () async => '',
          () async => ' token ',
          () async => 'token\nheader',
          () async => throw StateError('secret-value'),
        ]) {
          final client = makeClient(mock, token: provider);
          await expectLater(
            client.readInventory(),
            throwsA(
              isA<CoordinatorAuthenticationException>().having(
                (error) => error.toString(),
                'redacted text',
                isNot(contains('secret-value')),
              ),
            ),
          );
        }
        expect(requests, 0);
      },
    );

    test('rejects oversized request and response bodies', () async {
      final requestLimited = makeClient(
        MockClient((_) async => jsonResponse({'ok': true})),
        limits: const CoordinatorClientLimits(maxRequestBytes: 64),
      );
      final project = CoordinatorProjectTarget(
        repoId: 'repo',
        canonicalRoot: '/${List.filled(200, 'p').join()}',
      );
      await expectLater(
        requestLimited.actOnProject(
          target: project,
          actor: CoordinatorActor('actor'),
          action: CoordinatorProjectAction.stop,
        ),
        throwsA(isA<CoordinatorBodyTooLargeException>()),
      );

      final responseLimited = makeClient(
        MockClient((_) async => jsonResponse({'padding': 'x' * 1000})),
        limits: const CoordinatorClientLimits(maxInventoryBytes: 100),
      );
      await expectLater(
        responseLimited.readInventory(),
        throwsA(isA<CoordinatorBodyTooLargeException>()),
      );
    });

    test('applies a deadline to the complete request', () async {
      final client = makeClient(
        MockClient((_) async {
          await Completer<void>().future;
          return jsonResponse({});
        }),
        limits: const CoordinatorClientLimits(
          inventoryTimeout: Duration(milliseconds: 10),
        ),
      );
      await expectLater(
        client.readInventory(),
        throwsA(isA<CoordinatorTimeoutException>()),
      );
    });

    test(
      'mutation timeout after HTTP dispatch reports an unknown outcome',
      () async {
        const credential = 'private-timeout-token';
        const privateProject = '/srv/private-timeout-body';
        final client = makeClient(
          MockClient((_) async {
            await Completer<void>().future;
            return jsonResponse({'ok': true});
          }),
          token: () async => credential,
          limits: const CoordinatorClientLimits(
            lifecycleTimeout: Duration(milliseconds: 10),
          ),
        );

        try {
          await client.actOnProject(
            target: CoordinatorProjectTarget(
              repoId: 'repo-private',
              canonicalRoot: privateProject,
            ),
            actor: CoordinatorActor('private-body-actor'),
            action: CoordinatorProjectAction.stop,
          );
          fail('Expected an unknown mutation outcome.');
        } on CoordinatorMutationOutcomeUnknownException catch (error) {
          expect(error.method, 'POST');
          expect(error.path, '/v1/projects/stop');
          expect(error.timeout, const Duration(milliseconds: 10));
          expect(error.toString(), isNot(contains(credential)));
          expect(error.toString(), isNot(contains(privateProject)));
          expect(error.toString(), isNot(contains('private-body-actor')));
        }
      },
    );

    test('mutation transport break reports an unknown outcome', () async {
      const credential = 'private-transport-token';
      const privateProject = '/srv/private-transport-body';
      final client = makeClient(
        MockClient(
          (_) async => throw http.ClientException('socket broke: $credential'),
        ),
        token: () async => credential,
      );

      try {
        await client.actOnProject(
          target: CoordinatorProjectTarget(
            repoId: 'repo-private',
            canonicalRoot: privateProject,
          ),
          actor: CoordinatorActor('private-transport-actor'),
          action: CoordinatorProjectAction.restart,
        );
        fail('Expected an unknown mutation outcome.');
      } on CoordinatorMutationOutcomeUnknownException catch (error) {
        expect(error.method, 'POST');
        expect(error.path, '/v1/projects/restart');
        expect(error.toString(), isNot(contains(credential)));
        expect(error.toString(), isNot(contains(privateProject)));
        expect(error.toString(), isNot(contains('socket broke')));
      }
    });

    test('read-only POST timeout remains an ordinary timeout', () async {
      final client = makeClient(
        MockClient((_) async {
          await Completer<void>().future;
          return jsonResponse({'text': ''});
        }),
        limits: const CoordinatorClientLimits(
          requestTimeout: Duration(milliseconds: 10),
        ),
      );

      await expectLater(
        client.readServerLogs(
          CoordinatorServerTarget(
            id: 'server-1',
            repoId: 'repo-1',
            projectRoot: '/srv/project',
            name: 'web',
          ),
        ),
        throwsA(isA<CoordinatorTimeoutException>()),
      );
    });

    test(
      'read-only status transport break remains a transport failure',
      () async {
        final client = makeClient(
          MockClient((_) async => throw http.ClientException('offline')),
        );

        await expectLater(
          client.actOnProject(
            target: CoordinatorProjectTarget(
              repoId: 'repo-1',
              canonicalRoot: '/srv/project',
            ),
            actor: CoordinatorActor('operator'),
            action: CoordinatorProjectAction.status,
          ),
          throwsA(isA<CoordinatorTransportException>()),
        );
      },
    );

    test('pre-dispatch mutation timeout never sends later', () async {
      var requests = 0;
      final client = makeClient(
        MockClient((_) async {
          requests += 1;
          return jsonResponse({'ok': true});
        }),
        token: () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return 'fixture-token';
        },
        limits: const CoordinatorClientLimits(
          lifecycleTimeout: Duration(milliseconds: 5),
        ),
      );

      await expectLater(
        client.actOnProject(
          target: CoordinatorProjectTarget(
            repoId: 'repo-1',
            canonicalRoot: '/srv/project',
          ),
          actor: CoordinatorActor('operator'),
          action: CoordinatorProjectAction.stop,
        ),
        throwsA(isA<CoordinatorTimeoutException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(requests, 0);
    });
  });

  group('HTTP and strict JSON failures', () {
    test('surfaces safe structured HTTP errors', () async {
      final client = makeClient(
        MockClient(
          (_) async =>
              jsonResponse({'error': 'matching lease not found'}, status: 400),
        ),
      );
      await expectLater(
        client.readInventory(),
        throwsA(
          isA<CoordinatorHttpException>()
              .having((error) => error.statusCode, 'status', 400)
              .having(
                (error) => error.message,
                'message',
                'matching lease not found',
              ),
        ),
      );
    });

    test('redacts credentials echoed by an HTTP error response', () async {
      const credential = 'private-bearer-value';
      final client = makeClient(
        MockClient(
          (_) async => jsonResponse({
            'error': 'Authorization failed for Bearer $credential',
            'authorization': 'Bearer $credential',
            'nested': {
              'access_token': credential,
              'detail': 'credential=$credential',
            },
          }, status: 401),
        ),
        token: () async => credential,
      );

      try {
        await client.readInventory();
        fail('Expected a CoordinatorHttpException.');
      } on CoordinatorHttpException catch (error) {
        expect(error.toString(), isNot(contains(credential)));
        expect(error.response.toString(), isNot(contains(credential)));
        expect(error.response?['authorization'], '[redacted]');
      }
    });

    test(
      'rejects malformed, non-object, empty, and non-JSON successes',
      () async {
        final responses = <http.Response>[
          http.Response(
            '{bad',
            200,
            headers: {'content-type': 'application/json'},
          ),
          http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          ),
          http.Response('', 200, headers: {'content-type': 'application/json'}),
          http.Response('{}', 200, headers: {'content-type': 'text/plain'}),
        ];
        for (final response in responses) {
          final client = makeClient(MockClient((_) async => response));
          await expectLater(
            client.readInventory(),
            throwsA(isA<CoordinatorProtocolException>()),
          );
        }
      },
    );

    test('rejects invalid UTF-8 in a success body', () async {
      final client = makeClient(
        MockClient(
          (_) async => http.Response.bytes(
            [0xff, 0xfe],
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        client.readInventory(),
        throwsA(isA<CoordinatorProtocolException>()),
      );
    });
  });

  group('semantic failures', () {
    for (final fixture in <Map<String, Object?>>[
      {'ok': false},
      {'partial': true},
      {'needs_attention': true},
      {'blocked': true},
      {'status': 'blocked'},
      {'status': 'failed'},
      {'status': 'partial'},
      {
        'status': 'unhealthy',
        'health': {'ok': false},
      },
      {
        'result': {'status': 'degraded'},
      },
      {
        'result': {'ok': false, 'message': 'nested failure'},
      },
      {
        'ok': true,
        'action_errors': ['one resource failed'],
      },
    ]) {
      test('rejects ${jsonEncode(fixture)} even with HTTP 200', () async {
        final client = makeClient(
          MockClient((_) async => jsonResponse(fixture)),
        );
        await expectLater(
          client.actOnProject(
            target: CoordinatorProjectTarget(
              repoId: 'repo-1',
              canonicalRoot: '/srv/project',
            ),
            actor: CoordinatorActor('operator'),
            action: CoordinatorProjectAction.stop,
          ),
          throwsA(isA<CoordinatorSemanticException>()),
        );
      });
    }

    test('accepts an explicitly complete action result', () async {
      final client = makeClient(
        MockClient(
          (_) async => jsonResponse({
            'ok': true,
            'partial': false,
            'needs_attention': false,
            'status': 'completed',
          }),
        ),
      );
      final result = await client.actOnProject(
        target: CoordinatorProjectTarget(
          repoId: 'repo-1',
          canonicalRoot: '/srv/project',
        ),
        actor: CoordinatorActor('operator'),
        action: CoordinatorProjectAction.stop,
      );
      expect(result.ok, isTrue);
      expect(result.status, 'completed');
    });

    test('rejects an action response without affirmative evidence', () async {
      final client = makeClient(MockClient((_) async => jsonResponse({})));

      await expectLater(
        client.actOnProject(
          target: CoordinatorProjectTarget(
            repoId: 'repo-1',
            canonicalRoot: '/srv/project',
          ),
          actor: CoordinatorActor('operator'),
          action: CoordinatorProjectAction.stop,
        ),
        throwsA(isA<CoordinatorProtocolException>()),
      );
    });

    test('accepts only endpoint-appropriate affirmative states', () async {
      final projectClient = makeClient(
        MockClient((_) async => jsonResponse({'status': 'stopped'})),
      );
      final projectResult = await projectClient.actOnProject(
        target: CoordinatorProjectTarget(
          repoId: 'repo-1',
          canonicalRoot: '/srv/project',
        ),
        actor: CoordinatorActor('operator'),
        action: CoordinatorProjectAction.stop,
      );
      expect(projectResult.status, 'stopped');

      final assignmentClient = makeClient(
        MockClient((_) async => jsonResponse({'status': 'active'})),
      );
      final assignmentResult = await assignmentClient.assignPort(
        target: CoordinatorPortAssignmentTarget(
          repoId: 'repo-1',
          projectRoot: '/srv/project',
          serverName: 'web',
        ),
        actor: CoordinatorActor('operator'),
        port: 3301,
      );
      expect(assignmentResult.status, 'active');

      final legacyAssignmentClient = makeClient(
        MockClient(
          (_) async => jsonResponse({
            'project': '/srv/project',
            'name': 'web',
            'port': 3301,
            'source': 'port_assign',
          }),
        ),
      );
      final legacyAssignmentResult = await legacyAssignmentClient.assignPort(
        target: CoordinatorPortAssignmentTarget(
          repoId: 'repo-1',
          projectRoot: '/srv/project',
          serverName: 'web',
        ),
        actor: CoordinatorActor('operator'),
        port: 3301,
      );
      expect(legacyAssignmentResult.status, isNull);

      final mismatchedAssignmentClient = makeClient(
        MockClient(
          (_) async => jsonResponse({
            'project': '/srv/project',
            'name': 'another-server',
            'port': 3301,
          }),
        ),
      );
      await expectLater(
        mismatchedAssignmentClient.assignPort(
          target: CoordinatorPortAssignmentTarget(
            repoId: 'repo-1',
            projectRoot: '/srv/project',
            serverName: 'web',
          ),
          actor: CoordinatorActor('operator'),
          port: 3301,
        ),
        throwsA(isA<CoordinatorProtocolException>()),
      );

      final wrongStateClient = makeClient(
        MockClient((_) async => jsonResponse({'status': 'active'})),
      );
      await expectLater(
        wrongStateClient.actOnProject(
          target: CoordinatorProjectTarget(
            repoId: 'repo-1',
            canonicalRoot: '/srv/project',
          ),
          actor: CoordinatorActor('operator'),
          action: CoordinatorProjectAction.stop,
        ),
        throwsA(isA<CoordinatorProtocolException>()),
      );

      final terminalClient = makeClient(
        MockClient((_) async => jsonResponse({'status': 'succeeded'})),
      );
      final terminalResult = await terminalClient.actOnProject(
        target: CoordinatorProjectTarget(
          repoId: 'repo-1',
          canonicalRoot: '/srv/project',
        ),
        actor: CoordinatorActor('operator'),
        action: CoordinatorProjectAction.restart,
      );
      expect(terminalResult.status, 'succeeded');
    });

    test(
      'accepts a completed stop snapshot whose health is now false',
      () async {
        final client = makeClient(
          MockClient(
            (_) async => jsonResponse({
              'status': 'stopped',
              'health': {'ok': false, 'classification': 'not_running'},
            }),
          ),
        );

        final result = await client.actOnProject(
          target: CoordinatorProjectTarget(
            repoId: 'repo-1',
            canonicalRoot: '/srv/project',
          ),
          actor: CoordinatorActor('operator'),
          action: CoordinatorProjectAction.stop,
        );

        expect(result.status, 'stopped');
      },
    );

    for (final failure in <Map<String, Object?>>[
      {'ok': false},
      {'partial': true},
      {'needs_attention': true},
      {
        'action_errors': ['one inventory action failed'],
      },
    ]) {
      test(
        'inventory rejects ${jsonEncode(failure)} even with HTTP 200',
        () async {
          final fixture = normalizedInventoryFixture()..addAll(failure);
          final client = makeClient(
            MockClient((_) async => jsonResponse(fixture)),
          );

          await expectLater(
            client.readInventory(),
            throwsA(isA<CoordinatorSemanticException>()),
          );
        },
      );
    }

    test('inventory accepts a complete v1 payload without ok', () async {
      final fixture = normalizedInventoryFixture();
      expect(fixture, isNot(contains('ok')));
      final client = makeClient(MockClient((_) async => jsonResponse(fixture)));

      final inventory = await client.readInventory();

      expect(inventory.projects.single.id, 'repo-1');
    });

    test('redacts credentials from retained semantic evidence', () async {
      const credential = 'private-bearer-value';
      final client = makeClient(
        MockClient(
          (_) async => jsonResponse({
            'ok': false,
            'message': 'operation failed with $credential',
            'token': credential,
          }),
        ),
        token: () async => credential,
      );

      try {
        await client.actOnProject(
          target: CoordinatorProjectTarget(
            repoId: 'repo-1',
            canonicalRoot: '/srv/project',
          ),
          actor: CoordinatorActor('operator'),
          action: CoordinatorProjectAction.stop,
        );
        fail('Expected a CoordinatorSemanticException.');
      } on CoordinatorSemanticException catch (error) {
        expect(error.toString(), isNot(contains(credential)));
        expect(error.response.toString(), isNot(contains(credential)));
        expect(error.response['token'], '[redacted]');
      }
    });
  });

  test('close prevents reuse and optionally owns the HTTP client', () async {
    final client = makeClient(
      MockClient((_) async => jsonResponse(normalizedInventoryFixture())),
    );
    client.close();
    client.close();
    await expectLater(
      client.readInventory(),
      throwsA(isA<CoordinatorTransportException>()),
    );
  });
}
