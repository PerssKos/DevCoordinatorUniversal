import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:release_update/release_update.dart';
import 'package:test/test.dart';

void main() {
  group('GitHubReleaseSource', () {
    test(
      'requests latest stable release and parses a v-prefixed SemVer',
      () async {
        late http.Request capturedRequest;
        final client = MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode(_githubReleaseJson()),
            200,
            headers: const <String, String>{'etag': 'W/"release-42"'},
          );
        });
        final source = GitHubReleaseSource(
          client: client,
          owner: 'acme',
          repository: 'desktop-app',
          userAgent: 'acme-desktop/1.0',
        );

        final result = await source.fetchLatest();

        expect(
          capturedRequest.url,
          Uri.parse(
            'https://api.github.com/repos/acme/desktop-app/releases/latest',
          ),
        );
        expect(
          capturedRequest.headers['accept'],
          'application/vnd.github+json',
        );
        expect(capturedRequest.headers['x-github-api-version'], '2022-11-28');
        expect(capturedRequest.headers['user-agent'], 'acme-desktop/1.0');
        expect(capturedRequest.headers, isNot(contains('authorization')));
        expect(capturedRequest.headers, isNot(contains('if-none-match')));

        expect(result, isA<ReleaseFetched>());
        final fetched = result as ReleaseFetched;
        expect(fetched.etag, 'W/"release-42"');
        expect(fetched.release.id, 42);
        expect(fetched.release.tagName, 'v2.4.1');
        expect(fetched.release.version, Version(2, 4, 1));
        expect(fetched.release.name, 'Desktop 2.4.1');
        expect(fetched.release.notes, 'Security and reliability fixes.');
        expect(
          fetched.release.pageUri,
          Uri.parse('https://github.com/acme/desktop-app/releases/tag/v2.4.1'),
        );
        expect(fetched.release.publishedAt, DateTime.utc(2026, 7, 25, 12, 30));
        expect(
          source.sourceId,
          'github:https://api.github.com/repos/acme/desktop-app/releases/latest',
        );
      },
    );

    test('sends If-None-Match and represents a 304 response', () async {
      late http.Request capturedRequest;
      final source = GitHubReleaseSource(
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            '',
            304,
            headers: const <String, String>{'etag': '"still-current"'},
          );
        }),
        owner: 'acme',
        repository: 'desktop-app',
      );

      final result = await source.fetchLatest(ifNoneMatch: 'W/"cached"');

      expect(capturedRequest.headers['if-none-match'], 'W/"cached"');
      expect(result, isA<ReleaseNotModified>());
      expect(result.etag, '"still-current"');
    });

    test('preserves an Enterprise API path prefix', () {
      final source = GitHubReleaseSource(
        client: MockClient((_) async => http.Response('', 304)),
        owner: 'acme',
        repository: 'desktop-app',
        apiBaseUri: Uri.parse('https://github.example/api/v3/'),
      );

      expect(
        source.endpoint,
        Uri.parse(
          'https://github.example/api/v3/repos/acme/desktop-app/releases/latest',
        ),
      );
    });

    test(
      'rejects path and header injection at construction or fetch',
      () async {
        final client = MockClient((_) async => http.Response('', 304));

        expect(
          () => GitHubReleaseSource(
            client: client,
            owner: '../acme',
            repository: 'app',
          ),
          throwsArgumentError,
        );
        expect(
          () => GitHubReleaseSource(
            client: client,
            owner: 'acme',
            repository: 'app',
            userAgent: 'app\r\nAuthorization: secret',
          ),
          throwsArgumentError,
        );

        final source = GitHubReleaseSource(
          client: client,
          owner: 'acme',
          repository: 'app',
        );
        await expectLater(
          source.fetchLatest(ifNoneMatch: '"ok"\nX-Evil: true'),
          throwsArgumentError,
        );
        await expectLater(
          source.fetchLatest(ifNoneMatch: '"ok"\u0000'),
          throwsArgumentError,
        );
        await expectLater(
          source.fetchLatest(ifNoneMatch: '"ok"\u007f'),
          throwsArgumentError,
        );
        expect(
          () => GitHubReleaseSource(
            client: client,
            owner: 'acme',
            repository: 'app',
            apiBaseUri: Uri.parse('http://github.example/api/v3/'),
          ),
          throwsArgumentError,
        );
      },
    );

    group('HTTP and transport errors', () {
      test('returns bounded diagnostics for a non-success status', () async {
        final source = GitHubReleaseSource(
          client: MockClient(
            (_) async => http.Response(
              'x' * 3000,
              404,
              headers: const <String, String>{
                'x-github-request-id': 'request-1',
              },
            ),
          ),
          owner: 'acme',
          repository: 'missing',
        );

        await expectLater(
          source.fetchLatest(),
          throwsA(
            isA<ReleaseHttpException>()
                .having((error) => error.statusCode, 'statusCode', 404)
                .having(
                  (error) => error.responseBody.length,
                  'bounded body length',
                  2048,
                )
                .having((error) => error.requestId, 'requestId', 'request-1')
                .having(
                  (error) => error.isRateLimited,
                  'isRateLimited',
                  isFalse,
                ),
          ),
        );
      });

      test('exposes rate-limit response metadata', () async {
        final source = GitHubReleaseSource(
          client: MockClient(
            (_) async => http.Response(
              '{"message":"API rate limit exceeded"}',
              403,
              headers: const <String, String>{
                'retry-after': '60',
                'x-ratelimit-remaining': '0',
                'x-ratelimit-reset': '1785000000',
              },
            ),
          ),
          owner: 'acme',
          repository: 'app',
        );

        await expectLater(
          source.fetchLatest(),
          throwsA(
            isA<ReleaseHttpException>()
                .having((error) => error.isRateLimited, 'isRateLimited', isTrue)
                .having((error) => error.retryAfter, 'retryAfter', '60')
                .having(
                  (error) => error.rateLimitReset,
                  'rateLimitReset',
                  '1785000000',
                ),
          ),
        );
      });

      test('recognizes a secondary 403 rate limit from Retry-After', () async {
        final source = GitHubReleaseSource(
          client: MockClient(
            (_) async => http.Response(
              '{"message":"secondary rate limit"}',
              403,
              headers: const <String, String>{'retry-after': '30'},
            ),
          ),
          owner: 'acme',
          repository: 'app',
        );

        await expectLater(
          source.fetchLatest(),
          throwsA(
            isA<ReleaseHttpException>().having(
              (error) => error.isRateLimited,
              'isRateLimited',
              isTrue,
            ),
          ),
        );
      });

      test('wraps package:http client failures', () async {
        final source = GitHubReleaseSource(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
          owner: 'acme',
          repository: 'app',
        );

        await expectLater(
          source.fetchLatest(),
          throwsA(
            isA<ReleaseTransportException>().having(
              (error) => error.cause,
              'cause',
              isA<http.ClientException>(),
            ),
          ),
        );
      });

      test('turns a request timeout into a transport failure', () async {
        final never = Completer<http.Response>();
        final source = GitHubReleaseSource(
          client: MockClient((_) => never.future),
          owner: 'acme',
          repository: 'app',
          timeout: const Duration(milliseconds: 1),
        );

        await expectLater(
          source.fetchLatest(),
          throwsA(
            isA<ReleaseTransportException>().having(
              (error) => error.cause,
              'cause',
              isA<TimeoutException>(),
            ),
          ),
        );
      });
    });

    group('malformed successful responses', () {
      test('rejects invalid UTF-8 or JSON', () async {
        final invalidUtf8 = GitHubReleaseSource(
          client: MockClient(
            (_) async => http.Response.bytes(<int>[0xff, 0xfe], 200),
          ),
          owner: 'acme',
          repository: 'app',
        );
        final invalidJson = GitHubReleaseSource(
          client: MockClient((_) async => http.Response('{', 200)),
          owner: 'acme',
          repository: 'app',
        );

        await expectLater(
          invalidUtf8.fetchLatest(),
          throwsA(isA<ReleasePayloadException>()),
        );
        await expectLater(
          invalidJson.fetchLatest(),
          throwsA(isA<ReleasePayloadException>()),
        );
      });

      test('rejects a non-object JSON root', () async {
        final source = _sourceReturningJson(<Object?>[]);

        await expectLater(
          source.fetchLatest(),
          throwsA(isA<ReleasePayloadException>()),
        );
      });

      final malformedCases = <String, void Function(Map<String, Object?>)>{
        'missing id': (json) => json.remove('id'),
        'non-integer id': (json) => json['id'] = 42.5,
        'non-positive id': (json) => json['id'] = 0,
        'missing tag': (json) => json.remove('tag_name'),
        'invalid SemVer': (json) => json['tag_name'] = 'release-two',
        'relative page URL': (json) => json['html_url'] = '/release/v2.4.1',
        'insecure page URL': (json) =>
            json['html_url'] = 'http://github.example/release/v2.4.1',
        'credential-bearing page URL': (json) => json['html_url'] =
            'https://maintainer:secret@github.example/release/v2.4.1',
        'hostless page URL': (json) =>
            json['html_url'] = 'https:release/v2.4.1',
        'invalid publication timestamp': (json) =>
            json['published_at'] = 'eventually',
        'draft response': (json) => json['draft'] = true,
        'prerelease response': (json) => json['prerelease'] = true,
        'non-string notes': (json) => json['body'] = <Object?>[],
      };

      for (final entry in malformedCases.entries) {
        test('rejects ${entry.key}', () async {
          final json = _githubReleaseJson();
          entry.value(json);

          await expectLater(
            _sourceReturningJson(json).fetchLatest(),
            throwsA(isA<ReleasePayloadException>()),
          );
        });
      }
    });
  });

  group('UpdatePolicy', () {
    final policy = UpdatePolicy();
    final current = Version(2, 0, 0);

    test('prompts only for a newer semantic version', () {
      final decision = policy.evaluate(
        currentVersion: current,
        latestRelease: _release('2.1.0'),
        now: _now,
      );

      expect(decision.kind, UpdateDecisionKind.updateAvailable);
      expect(decision.shouldPrompt, isTrue);
    });

    test('marks equal precedence as up to date, including build metadata', () {
      final decision = policy.evaluate(
        currentVersion: Version.parse('2.0.0+installed.5'),
        latestRelease: _release('2.0.0+remote.9'),
        now: _now,
      );

      expect(decision.kind, UpdateDecisionKind.upToDate);
      expect(decision.shouldPrompt, isFalse);
    });

    test('allows a stable release after an installed prerelease', () {
      final decision = policy.evaluate(
        currentVersion: Version.parse('2.0.0-rc.1'),
        latestRelease: _release('2.0.0'),
        now: _now,
      );

      expect(decision.kind, UpdateDecisionKind.updateAvailable);
    });

    test('never prompts for a remote downgrade', () {
      final decision = policy.evaluate(
        currentVersion: Version(3, 0, 0),
        latestRelease: _release('2.9.9'),
        now: _now,
      );

      expect(decision.kind, UpdateDecisionKind.remoteOlder);
      expect(decision.shouldPrompt, isFalse);
    });

    test('ignore suppresses through its version but not a newer release', () {
      final suppression = policy.ignore(
        state: const UpdateSuppression.none(),
        version: Version(2, 1, 0),
      );

      final ignored = policy.evaluate(
        currentVersion: current,
        latestRelease: _release('2.1.0'),
        suppression: suppression,
        now: _now,
      );
      final newer = policy.evaluate(
        currentVersion: current,
        latestRelease: _release('2.1.1'),
        suppression: suppression,
        now: _now,
      );

      expect(ignored.kind, UpdateDecisionKind.ignored);
      expect(ignored.shouldPrompt, isFalse);
      expect(newer.kind, UpdateDecisionKind.updateAvailable);
    });

    test('ignore threshold never moves backwards', () {
      final higher = policy.ignore(
        state: const UpdateSuppression.none(),
        version: Version(3, 0, 0),
      );
      final attemptedLower = policy.ignore(
        state: higher,
        version: Version(2, 5, 0),
      );

      expect(attemptedLower.ignoredThroughVersion, Version(3, 0, 0));
    });

    test('remind later suppresses until, but not at, its deadline', () {
      final sixHourPolicy = UpdatePolicy(
        remindLaterDuration: const Duration(hours: 6),
      );
      final suppression = sixHourPolicy.remindLater(
        state: const UpdateSuppression.none(),
        version: Version(2, 1, 0),
        now: _now,
      );

      final before = sixHourPolicy.evaluate(
        currentVersion: current,
        latestRelease: _release('2.1.0'),
        suppression: suppression,
        now: _now.add(const Duration(hours: 5, minutes: 59)),
      );
      final atDeadline = sixHourPolicy.evaluate(
        currentVersion: current,
        latestRelease: _release('2.1.0'),
        suppression: suppression,
        now: _now.add(const Duration(hours: 6)),
      );

      expect(before.kind, UpdateDecisionKind.deferred);
      expect(before.nextPromptAt, _now.add(const Duration(hours: 6)));
      expect(atDeadline.kind, UpdateDecisionKind.updateAvailable);
    });

    test('a newer release bypasses an older release deferral', () {
      final suppression = policy.remindLater(
        state: const UpdateSuppression.none(),
        version: Version(2, 1, 0),
        now: _now,
      );

      final decision = policy.evaluate(
        currentVersion: current,
        latestRelease: _release('2.2.0'),
        suppression: suppression,
        now: _now.add(const Duration(minutes: 1)),
      );

      expect(decision.kind, UpdateDecisionKind.updateAvailable);
    });

    test('a stale Later response cannot lower an existing deferral', () {
      final newerDeferral = policy.remindLater(
        state: const UpdateSuppression.none(),
        version: Version(2, 2, 0),
        now: _now,
      );
      final staleResponse = policy.remindLater(
        state: newerDeferral,
        version: Version(2, 1, 0),
        now: _now.add(const Duration(minutes: 1)),
      );

      expect(staleResponse, newerDeferral);
      expect(staleResponse.deferredThroughVersion, Version(2, 2, 0));
    });

    test('repeated Later cannot shorten the same version deadline', () {
      final later = policy.remindLater(
        state: const UpdateSuppression.none(),
        version: Version(2, 1, 0),
        now: _now,
      );
      final stale = policy.remindLater(
        state: later,
        version: Version(2, 1, 0),
        now: _now.subtract(const Duration(hours: 1)),
      );

      expect(stale.deferredUntil, later.deferredUntil);
    });

    test('suppression JSON round-trips and validates the deferred pair', () {
      final ignored = policy.ignore(
        state: const UpdateSuppression.none(),
        version: Version(2, 1, 0),
      );
      final suppression = policy.remindLater(
        state: ignored,
        version: Version(2, 2, 0),
        now: _now,
      );

      expect(UpdateSuppression.fromJson(suppression.toJson()), suppression);
      expect(
        () => UpdateSuppression.fromJson(<String, Object?>{
          'deferredThroughVersion': '2.1.0',
        }),
        throwsFormatException,
      );
      expect(
        () => UpdateSuppression.fromJson(<String, Object?>{
          'ignoredThroughVersion': 'not-semver',
        }),
        throwsFormatException,
      );
    });

    test('rejects a non-positive remind-later duration', () {
      expect(
        () => UpdatePolicy(remindLaterDuration: Duration.zero),
        throwsArgumentError,
      );
    });
  });

  group('ReleaseUpdateChecker', () {
    test('turns a 200 fetch into a decision and persistable cache', () async {
      final release = _release('2.1.0');
      final source = _FakeReleaseSource(
        sourceId: 'github:acme/app',
        result: ReleaseFetched(release: release, etag: '"fresh"'),
      );
      final checker = ReleaseUpdateChecker(source: source);

      final result = await checker.check(
        currentVersion: Version(2, 0, 0),
        now: _now,
      );

      expect(source.receivedEtag, isNull);
      expect(result.usedCachedRelease, isFalse);
      expect(result.decision.kind, UpdateDecisionKind.updateAvailable);
      expect(result.cache.sourceId, source.sourceId);
      expect(result.cache.release, release);
      expect(result.cache.etag, '"fresh"');
      expect(result.cache.validatedAt, _now);
      expect(ReleaseCacheEntry.fromJson(result.cache.toJson()), result.cache);
    });

    test('sends ETag and reuses cached release after 304', () async {
      final cachedRelease = _release('2.1.0');
      final cache = ReleaseCacheEntry(
        sourceId: 'github:acme/app',
        release: cachedRelease,
        etag: 'W/"cached"',
        validatedAt: _now.subtract(const Duration(days: 1)),
      );
      final source = _FakeReleaseSource(
        sourceId: 'github:acme/app',
        result: const ReleaseNotModified(etag: null),
      );

      final result = await ReleaseUpdateChecker(source: source).check(
        currentVersion: Version(2, 0, 0),
        cache: cache,
        reason: UpdateCheckReason.manual,
        now: _now,
      );

      expect(source.receivedEtag, 'W/"cached"');
      expect(result.usedCachedRelease, isTrue);
      expect(result.cache.release, same(cachedRelease));
      expect(result.cache.etag, 'W/"cached"');
      expect(result.cache.validatedAt, _now);
      expect(result.decision.kind, UpdateDecisionKind.updateAvailable);
    });

    test('uses a replacement ETag returned with 304', () async {
      final cache = ReleaseCacheEntry(
        sourceId: 'github:acme/app',
        release: _release('2.1.0'),
        etag: '"old"',
        validatedAt: _now,
      );
      final source = _FakeReleaseSource(
        sourceId: 'github:acme/app',
        result: const ReleaseNotModified(etag: '"new"'),
      );

      final result = await ReleaseUpdateChecker(source: source).check(
        currentVersion: Version(2, 0, 0),
        cache: cache,
        reason: UpdateCheckReason.manual,
        now: _now,
      );

      expect(result.cache.etag, '"new"');
    });

    test('rejects 304 when matching release metadata is unavailable', () async {
      final source = _FakeReleaseSource(
        sourceId: 'github:acme/app',
        result: const ReleaseNotModified(etag: '"orphan"'),
      );

      await expectLater(
        ReleaseUpdateChecker(
          source: source,
        ).check(currentVersion: Version(2, 0, 0), now: _now),
        throwsA(isA<ReleaseCacheMissException>()),
      );
    });

    test('does not leak an ETag across source identities', () async {
      final replacement = _release('2.2.0');
      final source = _FakeReleaseSource(
        sourceId: 'github:acme/new-app',
        result: ReleaseFetched(release: replacement, etag: '"new-repo"'),
      );
      final wrongCache = ReleaseCacheEntry(
        sourceId: 'github:acme/old-app',
        release: _release('9.0.0'),
        etag: '"wrong-repo"',
        validatedAt: _now,
      );

      final result = await ReleaseUpdateChecker(
        source: source,
      ).check(currentVersion: Version(2, 0, 0), cache: wrongCache, now: _now);

      expect(source.receivedEtag, isNull);
      expect(result.cache.release, replacement);
      expect(result.cache.sourceId, source.sourceId);
    });

    test('applies ignored policy to a freshly fetched release', () async {
      final release = _release('2.1.0');
      final source = _FakeReleaseSource(
        sourceId: 'github:acme/app',
        result: ReleaseFetched(release: release, etag: null),
      );
      final policy = UpdatePolicy();
      final suppression = policy.ignore(
        state: const UpdateSuppression.none(),
        version: release.version,
      );

      final result = await ReleaseUpdateChecker(source: source, policy: policy)
          .check(
            currentVersion: Version(2, 0, 0),
            suppression: suppression,
            now: _now,
          );

      expect(result.decision.kind, UpdateDecisionKind.ignored);
      expect(result.decision.shouldPrompt, isFalse);
    });

    group('automatic check schedule', () {
      test('skips the network while matching cache is fresh', () async {
        final cache = ReleaseCacheEntry(
          sourceId: 'github:acme/app',
          release: _release('2.1.0'),
          etag: '"cached"',
          validatedAt: _now.subtract(const Duration(hours: 23, minutes: 59)),
        );
        final source = _FakeReleaseSource(
          sourceId: 'github:acme/app',
          result: ReleaseFetched(release: _release('9.0.0'), etag: '"unused"'),
        );

        final result = await ReleaseUpdateChecker(
          source: source,
        ).check(currentVersion: Version(2, 0, 0), cache: cache, now: _now);

        expect(source.fetchCount, 0);
        expect(result.status, UpdateCheckStatus.skippedFreshCache);
        expect(result.networkChecked, isFalse);
        expect(result.usedCachedRelease, isTrue);
        expect(result.cache, same(cache));
      });

      test('checks at the exact interval boundary', () async {
        final cache = ReleaseCacheEntry(
          sourceId: 'github:acme/app',
          release: _release('2.1.0'),
          etag: '"cached"',
          validatedAt: _now.subtract(const Duration(hours: 24)),
        );
        final source = _FakeReleaseSource(
          sourceId: 'github:acme/app',
          result: const ReleaseNotModified(etag: null),
        );

        final result = await ReleaseUpdateChecker(
          source: source,
        ).check(currentVersion: Version(2, 0, 0), cache: cache, now: _now);

        expect(source.fetchCount, 1);
        expect(result.status, UpdateCheckStatus.notModified);
      });

      test('checks after a wall-clock rollback or source change', () async {
        final futureCache = ReleaseCacheEntry(
          sourceId: 'github:acme/app',
          release: _release('2.1.0'),
          etag: '"future"',
          validatedAt: _now.add(const Duration(hours: 1)),
        );
        final rollbackSource = _FakeReleaseSource(
          sourceId: 'github:acme/app',
          result: const ReleaseNotModified(etag: null),
        );
        await ReleaseUpdateChecker(source: rollbackSource).check(
          currentVersion: Version(2, 0, 0),
          cache: futureCache,
          now: _now,
        );

        final foreignSource = _FakeReleaseSource(
          sourceId: 'github:acme/other',
          result: ReleaseFetched(release: _release('2.2.0'), etag: '"other"'),
        );
        await ReleaseUpdateChecker(source: foreignSource).check(
          currentVersion: Version(2, 0, 0),
          cache: futureCache,
          now: _now,
        );

        expect(rollbackSource.fetchCount, 1);
        expect(foreignSource.fetchCount, 1);
        expect(foreignSource.receivedEtag, isNull);
      });

      test('manual reason bypasses a fresh cache', () async {
        final cache = ReleaseCacheEntry(
          sourceId: 'github:acme/app',
          release: _release('2.1.0'),
          etag: '"fresh"',
          validatedAt: _now,
        );
        final source = _FakeReleaseSource(
          sourceId: 'github:acme/app',
          result: const ReleaseNotModified(etag: null),
        );

        await ReleaseUpdateChecker(source: source).check(
          currentVersion: Version(2, 0, 0),
          cache: cache,
          reason: UpdateCheckReason.manual,
          now: _now,
        );

        expect(source.fetchCount, 1);
        expect(source.receivedEtag, '"fresh"');
      });
    });
  });

  test('ReleaseInfo rejects a tag/version mismatch in cache data', () {
    final release = _release('2.1.0');
    final json = release.toJson()..['version'] = '9.0.0';

    expect(() => ReleaseInfo.fromJson(json), throwsFormatException);
    expect(
      () => ReleaseInfo(
        id: 1,
        version: Version(9, 0, 0),
        tagName: 'v2.1.0',
        pageUri: Uri.parse('https://example.test/releases/v2.1.0'),
        publishedAt: _now,
      ),
      throwsArgumentError,
    );
  });

  test('ReleaseInfo rejects unsafe release destinations', () {
    for (final uri in <Uri>[
      Uri.parse('https:release/v2.1.0'),
      Uri.parse('https://user:secret@example.test/releases/v2.1.0'),
    ]) {
      expect(
        () => ReleaseInfo(
          id: 1,
          version: Version(2, 1, 0),
          tagName: 'v2.1.0',
          pageUri: uri,
          publishedAt: _now,
        ),
        throwsArgumentError,
      );
    }
  });
}

final DateTime _now = DateTime.utc(2026, 7, 25, 18);

Map<String, Object?> _githubReleaseJson() => <String, Object?>{
  'id': 42,
  'tag_name': 'v2.4.1',
  'name': 'Desktop 2.4.1',
  'body': 'Security and reliability fixes.',
  'html_url': 'https://github.com/acme/desktop-app/releases/tag/v2.4.1',
  'published_at': '2026-07-25T12:30:00Z',
  'draft': false,
  'prerelease': false,
};

GitHubReleaseSource _sourceReturningJson(Object? value) => GitHubReleaseSource(
  client: MockClient((_) async => http.Response(jsonEncode(value), 200)),
  owner: 'acme',
  repository: 'app',
);

ReleaseInfo _release(String versionText) {
  final version = Version.parse(versionText);
  return ReleaseInfo(
    id: versionText.hashCode.abs() + 1,
    version: version,
    tagName: 'v$versionText',
    name: 'Release $versionText',
    notes: 'Notes',
    pageUri: Uri.parse('https://example.test/releases/$versionText'),
    publishedAt: _now,
  );
}

final class _FakeReleaseSource implements ReleaseSource {
  _FakeReleaseSource({required this.sourceId, required this.result});

  @override
  final String sourceId;

  final ReleaseFetchResult result;
  String? receivedEtag;
  int fetchCount = 0;

  @override
  Future<ReleaseFetchResult> fetchLatest({String? ifNoneMatch}) async {
    fetchCount += 1;
    receivedEtag = ifNoneMatch;
    return result;
  }
}
