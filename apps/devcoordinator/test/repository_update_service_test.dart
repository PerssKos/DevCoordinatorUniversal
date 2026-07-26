import 'package:devcoordinator/core/update/repository_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:release_update/release_update.dart';

import 'support/fakes.dart';

void main() {
  test('rejects update destinations that can downgrade transport security', () {
    expect(
      () => RepositoryAppUpdateService(
        destinationUrl: 'http://downloads.example.test/app',
      ),
      throwsArgumentError,
    );
    expect(
      () => RepositoryAppUpdateService(
        destinationUrl: 'https://user:secret@downloads.example.test/app',
      ),
      throwsArgumentError,
    );
  });

  test('accepts an absolute HTTPS update destination', () {
    expect(
      () => RepositoryAppUpdateService(
        destinationUrl: 'https://downloads.example.test/app',
      ),
      returnsNormally,
    );
  });

  test(
    'reports an unconfigured release source only on manual checks',
    () async {
      final service = RepositoryAppUpdateService(repositorySlug: '');

      await expectLater(
        service.check(currentVersion: '1.0.0', manual: true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('UPDATE_REPOSITORY=owner/repository'),
          ),
        ),
      );

      final automatic = await service.check(
        currentVersion: '1.0.0',
        manual: false,
      );
      expect(automatic.message, isNull);
      expect(automatic.release, isNull);
    },
  );

  test('treats a false platform-launch result as a failed open', () async {
    final service = RepositoryAppUpdateService(
      destinationUrl: 'https://downloads.example.test/app',
      launcher: (_) async => false,
    );

    await expectLater(
      service.openRelease(releaseFixture()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Could not open'),
        ),
      ),
    );
  });

  test('opens only the exact configured GitHub repository release', () async {
    Uri? launched;
    final service = RepositoryAppUpdateService(
      repositorySlug: 'PerssKos/DevCoordinatorUniversal',
      launcher: (destination) async {
        launched = destination;
        return true;
      },
    );
    final release = _releaseAt(
      'https://github.com/PerssKos/DevCoordinatorUniversal/releases/tag/v2.0.0',
    );

    await service.openRelease(release);

    expect(launched, release.pageUri);
  });

  test('rejects cross-host and cross-repository release pages', () async {
    var launches = 0;
    final service = RepositoryAppUpdateService(
      repositorySlug: 'PerssKos/DevCoordinatorUniversal',
      launcher: (_) async {
        launches += 1;
        return true;
      },
    );

    for (final url in <String>[
      'https://updates.example.test/PerssKos/DevCoordinatorUniversal/releases/tag/v2.0.0',
      'https://github.com/PerssKos/OtherRepository/releases/tag/v2.0.0',
      'https://github.com/OtherOwner/DevCoordinatorUniversal/releases/tag/v2.0.0',
    ]) {
      await expectLater(
        service.openRelease(_releaseAt(url)),
        throwsA(isA<StateError>()),
        reason: url,
      );
    }

    expect(launches, 0);
  });

  test('rejects a foreign release page restored from a fresh cache', () async {
    final now = DateTime.utc(2026, 7, 26, 12);
    var networkRequests = 0;
    final service = RepositoryAppUpdateService(
      repositorySlug: 'PerssKos/DevCoordinatorUniversal',
      clock: () => now,
      httpClient: MockClient((_) async {
        networkRequests += 1;
        return http.Response('', 500);
      }),
    );
    final cache = ReleaseCacheEntry(
      sourceId:
          'github:https://api.github.com/repos/'
          'PerssKos/DevCoordinatorUniversal/releases/latest',
      release: _releaseAt(
        'https://updates.example.test/'
        'PerssKos/DevCoordinatorUniversal/releases/tag/v2.0.0',
      ),
      validatedAt: now,
    );

    await expectLater(
      service.check(
        currentVersion: '1.0.0',
        manual: false,
        releaseCache: cache.toJson(),
      ),
      throwsA(isA<StateError>()),
    );

    expect(networkRequests, 0);
  });
}

ReleaseInfo _releaseAt(String url) {
  return ReleaseInfo(
    id: 20,
    version: Version.parse('2.0.0'),
    tagName: 'v2.0.0',
    pageUri: Uri.parse(url),
    publishedAt: DateTime.utc(2026, 7, 26),
  );
}
