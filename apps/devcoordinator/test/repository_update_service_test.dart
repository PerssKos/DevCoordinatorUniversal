import 'dart:convert';

import 'package:devcoordinator/core/update/repository_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:release_update/release_update.dart';

void main() {
  test('rejects update destinations that can downgrade transport security', () {
    expect(
      () => RepositoryAppUpdateService(
        target: _androidDirect,
        destinationUrl: 'http://downloads.example.test/app',
      ),
      throwsArgumentError,
    );
    expect(
      () => RepositoryAppUpdateService(
        target: _androidDirect,
        destinationUrl: 'https://user:secret@downloads.example.test/app',
      ),
      throwsArgumentError,
    );
  });

  test('direct builds reject even an absolute HTTPS destination override', () {
    expect(
      () => RepositoryAppUpdateService(
        target: _androidDirect,
        destinationUrl: 'https://downloads.example.test/app',
      ),
      throwsArgumentError,
    );
  });

  test(
    'reports an unconfigured release source only on manual checks',
    () async {
      final service = RepositoryAppUpdateService(
        target: _androidDirect,
        repositorySlug: '',
      );

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

  test('rejects repository path-segment injection before transport', () async {
    for (final repository in <String>[
      '../repository',
      'owner/..',
      r'owner/repo\name',
    ]) {
      final service = RepositoryAppUpdateService(
        target: _androidDirect,
        repositorySlug: repository,
        httpClient: MockClient(
          (_) async => fail('transport must not be reached: $repository'),
        ),
      );

      await expectLater(
        service.check(currentVersion: '1.0.0', manual: true),
        throwsA(isA<StateError>()),
        reason: repository,
      );
    }
  });

  test('treats a false platform-launch result as a failed open', () async {
    final service = RepositoryAppUpdateService(
      target: _androidDirect,
      repositorySlug: 'PerssKos/DevCoordinatorUniversal',
      launcher: (_) async => false,
    );

    await expectLater(
      service.openRelease(
        _releaseAt(
          'https://github.com/PerssKos/DevCoordinatorUniversal/releases/tag/'
          'v2.0.0',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Could not open'),
        ),
      ),
    );
  });

  test('direct channel opens only the exact owned installer asset', () async {
    Uri? launched;
    final service = RepositoryAppUpdateService(
      target: _androidDirect,
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

    expect(launched, release.assets.single.downloadUri);
  });

  test('rejects cross-host and cross-repository release pages', () async {
    var launches = 0;
    final service = RepositoryAppUpdateService(
      target: _androidDirect,
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
      target: _androidDirect,
      repositorySlug: 'PerssKos/DevCoordinatorUniversal',
      clock: () => now,
      httpClient: MockClient((_) async {
        networkRequests += 1;
        return http.Response('', 500);
      }),
    );
    final cache = ReleaseCatalogCacheEntry(
      sourceId:
          'github-catalog:https://api.github.com/repos/'
          'PerssKos/DevCoordinatorUniversal/releases?per_page=20',
      releases: <ReleaseInfo>[
        _releaseAt(
          'https://updates.example.test/'
          'PerssKos/DevCoordinatorUniversal/releases/tag/v2.0.0',
        ),
      ],
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

  test(
    'current Android direct release remains eligible by exact asset',
    () async {
      final now = DateTime.utc(2026, 7, 26, 12);
      final service = RepositoryAppUpdateService(
        target: _androidDirect,
        repositorySlug: 'PerssKos/DevCoordinatorUniversal',
        clock: () => now,
        httpClient: _catalogClient(<Map<String, Object?>>[
          _githubReleaseJson(
            version: '0.2.0',
            assetNames: const <String>[
              'DevCoordinator-0.2.0-android.apk',
              'DevCoordinator-0.2.0-android.apk.sha256',
            ],
          ),
        ]),
      );

      final result = await service.check(currentVersion: '0.1.0', manual: true);

      expect(result.release?.version, Version(0, 2, 0));
      expect(result.message, 'Version 0.2.0 is available.');
      final persisted = ReleaseCatalogCacheEntry.fromJson(result.releaseCache!);
      expect(persisted.releases.single.assets, hasLength(2));
    },
  );

  test('Android-only latest is informational manually and silent automatically '
      'on macOS or Windows', () async {
    final catalog = <Map<String, Object?>>[
      _githubReleaseJson(
        version: '2.0.0',
        assetNames: const <String>[
          'DevCoordinator-2.0.0-android.apk',
          'macos-adhoc-smoke.zip',
          'windows-self-signed-smoke.msix',
        ],
      ),
    ];
    for (final target in <AppUpdateTarget>[_macosDirect, _windowsDirect]) {
      final manual = await RepositoryAppUpdateService(
        target: target,
        repositorySlug: 'PerssKos/DevCoordinatorUniversal',
        httpClient: _catalogClient(catalog),
      ).check(currentVersion: '1.0.0', manual: true);
      final automatic = await RepositoryAppUpdateService(
        target: target,
        repositorySlug: 'PerssKos/DevCoordinatorUniversal',
        httpClient: _catalogClient(catalog),
      ).check(currentVersion: '1.0.0', manual: false);

      expect(manual.release, isNull, reason: target.description);
      expect(
        manual.message,
        allOf(
          contains('Version 2.0.0 is published'),
          contains(target.expectedDirectAssetName(Version(2, 0, 0))),
          contains('20 most recent releases'),
        ),
        reason: target.description,
      );
      expect(automatic.release, isNull, reason: target.description);
      expect(automatic.message, isNull, reason: target.description);
    }
  });

  test(
    'selects highest newer compatible release from bounded catalog',
    () async {
      final service = RepositoryAppUpdateService(
        target: _macosDirect,
        repositorySlug: 'PerssKos/DevCoordinatorUniversal',
        httpClient: _catalogClient(<Map<String, Object?>>[
          _githubReleaseJson(
            id: 30,
            version: '3.0.0',
            assetNames: const <String>['DevCoordinator-3.0.0-android.apk'],
          ),
          _githubReleaseJson(
            id: 25,
            version: '2.5.0',
            assetNames: const <String>['DevCoordinator-2.5.0-macos.dmg'],
          ),
          _githubReleaseJson(
            id: 20,
            version: '2.0.0',
            assetNames: const <String>['DevCoordinator-2.0.0-macos.dmg'],
          ),
        ]),
      );

      final result = await service.check(currentVersion: '2.0.0', manual: true);

      expect(result.release?.version, Version(2, 5, 0));
      expect(result.message, 'Version 2.5.0 is available.');
    },
  );

  test(
    'manual compatibility messaging ignores SemVer build metadata',
    () async {
      final result = await RepositoryAppUpdateService(
        target: _macosDirect,
        repositorySlug: 'PerssKos/DevCoordinatorUniversal',
        httpClient: _catalogClient(<Map<String, Object?>>[
          _githubReleaseJson(
            version: '2.0.0+2',
            assetNames: const <String>['DevCoordinator-2.0.0+2-android.apk'],
          ),
        ]),
      ).check(currentVersion: '2.0.0+1', manual: true);

      expect(result.release, isNull);
      expect(result.message, 'You are using the latest published release.');
    },
  );

  test('rejects an exact-name asset outside the configured repo/tag', () async {
    final release = _githubReleaseJson(
      version: '2.0.0',
      assetNames: const <String>['DevCoordinator-2.0.0-windows.msix'],
    );
    final assets = release['assets']! as List<Object?>;
    final asset = assets.single! as Map<String, Object?>;
    asset['browser_download_url'] =
        'https://github.com/OtherOwner/DevCoordinatorUniversal/releases/'
        'download/v2.0.0/DevCoordinator-2.0.0-windows.msix';
    final service = RepositoryAppUpdateService(
      target: _windowsDirect,
      repositorySlug: 'PerssKos/DevCoordinatorUniversal',
      httpClient: _catalogClient(<Map<String, Object?>>[release]),
    );

    await expectLater(
      service.check(currentVersion: '1.0.0', manual: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('does not belong'),
        ),
      ),
    );
  });

  test(
    'old latest-only cache is discarded before catalog validation',
    () async {
      var requests = 0;
      String? receivedEtag;
      final client = MockClient((request) async {
        requests += 1;
        receivedEtag = request.headers['if-none-match'];
        return http.Response(
          jsonEncode(<Object?>[
            _githubReleaseJson(
              version: '2.0.0',
              assetNames: const <String>['DevCoordinator-2.0.0-android.apk'],
            ),
          ]),
          200,
        );
      });
      final oldCache = ReleaseCacheEntry(
        sourceId:
            'github:https://api.github.com/repos/'
            'PerssKos/DevCoordinatorUniversal/releases/latest',
        release: _releaseAt(
          'https://github.com/PerssKos/DevCoordinatorUniversal/releases/tag/'
          'v2.0.0',
        ),
        etag: '"latest-only"',
        validatedAt: DateTime.utc(2026, 7, 26),
      ).toJson();

      final result = await RepositoryAppUpdateService(
        target: _androidDirect,
        repositorySlug: 'PerssKos/DevCoordinatorUniversal',
        httpClient: client,
      ).check(currentVersion: '1.0.0', manual: false, releaseCache: oldCache);

      expect(requests, 1);
      expect(receivedEtag, isNull);
      expect(result.release?.version, Version(2, 0, 0));
    },
  );

  test('store channels validate platform and require an HTTPS destination', () {
    expect(
      () => AppUpdateTarget(
        platform: AppUpdatePlatform.windows,
        channel: AppUpdateDistributionChannel.play,
      ),
      throwsArgumentError,
    );
    expect(
      () => RepositoryAppUpdateService(
        target: AppUpdateTarget(
          platform: AppUpdatePlatform.android,
          channel: AppUpdateDistributionChannel.play,
        ),
        repositorySlug: 'PerssKos/DevCoordinatorUniversal',
      ),
      throwsArgumentError,
    );
    expect(
      AppUpdateDistributionChannel.parse('microsoft_store'),
      AppUpdateDistributionChannel.microsoftStore,
    );
    expect(
      () => AppUpdateDistributionChannel.parse('store'),
      throwsArgumentError,
    );
  });

  test(
    'each Store channel requires identity-bound marker and opens its app',
    () async {
      for (final entry in _storeTargets) {
        Uri? launched;
        final expectedDestination = Uri.parse(entry.destination);
        final marker = entry.target.expectedCompatibilityAssetName(
          Version(2, 0, 0),
          storeProductId: entry.productId,
        );
        final service = RepositoryAppUpdateService(
          target: entry.target,
          repositorySlug: 'PerssKos/DevCoordinatorUniversal',
          destinationUrl: entry.destination,
          storeProductId: entry.productId,
          launcher: (uri) async {
            launched = uri;
            return true;
          },
          httpClient: _catalogClient(<Map<String, Object?>>[
            _githubReleaseJson(version: '2.0.0', assetNames: <String>[marker]),
          ]),
        );

        final result = await service.check(
          currentVersion: '1.0.0',
          manual: true,
        );
        await service.openRelease(result.release!);

        expect(
          result.release?.version,
          Version(2, 0, 0),
          reason: entry.target.description,
        );
        expect(launched, expectedDestination, reason: entry.target.description);
      }
    },
  );

  test(
    'Android-only release is not compatible with any Store target',
    () async {
      final catalog = <Map<String, Object?>>[
        _githubReleaseJson(
          version: '2.0.0',
          assetNames: const <String>['DevCoordinator-2.0.0-android.apk'],
        ),
      ];

      for (final entry in _storeTargets) {
        final manual = await RepositoryAppUpdateService(
          target: entry.target,
          repositorySlug: 'PerssKos/DevCoordinatorUniversal',
          destinationUrl: entry.destination,
          storeProductId: entry.productId,
          httpClient: _catalogClient(catalog),
        ).check(currentVersion: '1.0.0', manual: true);
        final automatic = await RepositoryAppUpdateService(
          target: entry.target,
          repositorySlug: 'PerssKos/DevCoordinatorUniversal',
          destinationUrl: entry.destination,
          storeProductId: entry.productId,
          httpClient: _catalogClient(catalog),
        ).check(currentVersion: '1.0.0', manual: false);

        expect(manual.release, isNull, reason: entry.target.description);
        expect(
          manual.message,
          contains(
            entry.target.expectedCompatibilityAssetName(
              Version(2, 0, 0),
              storeProductId: entry.productId,
            ),
          ),
          reason: entry.target.description,
        );
        expect(automatic.release, isNull, reason: entry.target.description);
        expect(automatic.message, isNull, reason: entry.target.description);
      }
    },
  );

  test(
    'Store marker for another product identity is never compatible',
    () async {
      final wrongMarkers = <AppUpdateDistributionChannel, String>{
        AppUpdateDistributionChannel.play:
            'DevCoordinator-2.0.0-android-google-play-'
            'com.example.other.release.json',
        AppUpdateDistributionChannel.macAppStore:
            'DevCoordinator-2.0.0-macos-mac-app-store-'
            '9999999999.release.json',
        AppUpdateDistributionChannel.microsoftStore:
            'DevCoordinator-2.0.0-windows-microsoft-store-'
            '9ZZZZZZZZZZZ.release.json',
      };

      for (final entry in _storeTargets) {
        final result = await RepositoryAppUpdateService(
          target: entry.target,
          repositorySlug: 'PerssKos/DevCoordinatorUniversal',
          destinationUrl: entry.destination,
          storeProductId: entry.productId,
          httpClient: _catalogClient(<Map<String, Object?>>[
            _githubReleaseJson(
              version: '2.0.0',
              assetNames: <String>[wrongMarkers[entry.target.channel]!],
            ),
          ]),
        ).check(currentVersion: '1.0.0', manual: true);

        expect(result.release, isNull, reason: entry.target.description);
        expect(
          result.message,
          contains(
            entry.target.expectedCompatibilityAssetName(
              Version(2, 0, 0),
              storeProductId: entry.productId,
            ),
          ),
          reason: entry.target.description,
        );
      }
    },
  );

  test('Store destinations require official origin and exact app identity', () {
    final cases =
        <({AppUpdateTarget target, String destination, String productId})>[
          (
            target: _androidPlay,
            destination:
                'https://play.google.com/store/apps/details?id=com.example.other',
            productId: '',
          ),
          (
            target: _androidPlay,
            destination:
                'https://example.test/store/apps/details?'
                'id=io.github.holyglory.devcoordinator',
            productId: '',
          ),
          (
            target: _macosAppStore,
            destination: 'https://apps.apple.com/app/id1234567890',
            productId: '9999999999',
          ),
          (
            target: _windowsMicrosoftStore,
            destination: 'https://apps.microsoft.com/detail/9ABCDEFGHIJK',
            productId: '9ZZZZZZZZZZZ',
          ),
          (
            target: _windowsMicrosoftStore,
            destination: 'https://apps.microsoft.com/detail/9ABCDEFGHIJK',
            productId: '9ABCDEFGHıJK',
          ),
          (
            target: _windowsMicrosoftStore,
            destination: 'https://apps.microsoft.com/detail/9ABCDEFGHıJK',
            productId: '9ABCDEFGHIJK',
          ),
          (
            target: _windowsMicrosoftStore,
            destination: 'https://apps.microsoft.com/detail/9ABCDEFGHIJſ',
            productId: '9ABCDEFGHIJS',
          ),
          (
            target: _windowsMicrosoftStore,
            destination: 'https://apps.microsoft.com/detail/9ABCDEFGHIß',
            productId: '9ABCDEFGHISS',
          ),
        ];

    for (final entry in cases) {
      expect(
        () => RepositoryAppUpdateService(
          target: entry.target,
          repositorySlug: 'PerssKos/DevCoordinatorUniversal',
          destinationUrl: entry.destination,
          storeProductId: entry.productId,
        ),
        throwsArgumentError,
        reason: '${entry.target.description}: ${entry.destination}',
      );
    }
  });
}

ReleaseInfo _releaseAt(String url) {
  final version = Version.parse('2.0.0');
  final assetName = 'DevCoordinator-$version-android.apk';
  return ReleaseInfo(
    id: 20,
    version: version,
    tagName: 'v2.0.0',
    pageUri: Uri.parse(url),
    publishedAt: DateTime.utc(2026, 7, 26),
    assets: <ReleaseAsset>[
      ReleaseAsset(
        id: 200,
        name: assetName,
        downloadUri: Uri.parse(
          'https://github.com/PerssKos/DevCoordinatorUniversal/releases/'
          'download/v2.0.0/$assetName',
        ),
        contentType: 'application/vnd.android.package-archive',
        sizeInBytes: 4096,
      ),
    ],
  );
}

AppUpdateTarget get _androidDirect => AppUpdateTarget(
  platform: AppUpdatePlatform.android,
  channel: AppUpdateDistributionChannel.direct,
);

AppUpdateTarget get _macosDirect => AppUpdateTarget(
  platform: AppUpdatePlatform.macos,
  channel: AppUpdateDistributionChannel.direct,
);

AppUpdateTarget get _windowsDirect => AppUpdateTarget(
  platform: AppUpdatePlatform.windows,
  channel: AppUpdateDistributionChannel.direct,
);

AppUpdateTarget get _androidPlay => AppUpdateTarget(
  platform: AppUpdatePlatform.android,
  channel: AppUpdateDistributionChannel.play,
);

AppUpdateTarget get _macosAppStore => AppUpdateTarget(
  platform: AppUpdatePlatform.macos,
  channel: AppUpdateDistributionChannel.macAppStore,
);

AppUpdateTarget get _windowsMicrosoftStore => AppUpdateTarget(
  platform: AppUpdatePlatform.windows,
  channel: AppUpdateDistributionChannel.microsoftStore,
);

List<({AppUpdateTarget target, String destination, String productId})>
get _storeTargets =>
    <({AppUpdateTarget target, String destination, String productId})>[
      (
        target: _androidPlay,
        destination:
            'https://play.google.com/store/apps/details?'
            'id=io.github.holyglory.devcoordinator',
        productId: '',
      ),
      (
        target: _macosAppStore,
        destination: 'https://apps.apple.com/app/id1234567890',
        productId: '1234567890',
      ),
      (
        target: _windowsMicrosoftStore,
        destination: 'https://apps.microsoft.com/detail/9ABCDEFGHIJK',
        productId: '9ABCDEFGHIJK',
      ),
    ];

MockClient _catalogClient(List<Map<String, Object?>> releases) => MockClient((
  request,
) async {
  expect(request.url.path, '/repos/PerssKos/DevCoordinatorUniversal/releases');
  expect(request.url.queryParameters['per_page'], '20');
  return http.Response(jsonEncode(releases), 200);
});

Map<String, Object?> _githubReleaseJson({
  int id = 20,
  required String version,
  List<String> assetNames = const <String>[],
}) => <String, Object?>{
  'id': id,
  'tag_name': 'v$version',
  'name': 'DevCoordinator $version',
  'body': 'Release notes',
  'html_url':
      'https://github.com/PerssKos/DevCoordinatorUniversal/releases/tag/'
      'v$version',
  'published_at': '2026-07-26T12:00:00Z',
  'draft': false,
  'prerelease': false,
  'assets': <Object?>[
    for (var index = 0; index < assetNames.length; index += 1)
      <String, Object?>{
        'id': id * 100 + index + 1,
        'name': assetNames[index],
        'state': 'uploaded',
        'browser_download_url':
            'https://github.com/PerssKos/DevCoordinatorUniversal/releases/'
            'download/v$version/${assetNames[index]}',
        'content_type': 'application/octet-stream',
        'size': 4096,
      },
  ],
};
