# release_update

Pure Dart release discovery and prompt policy for applications published through
GitHub Releases.

The package:

- calls GitHub's latest stable release endpoint and a bounded stable-release
  catalog endpoint;
- sends and returns opaque `ETag` values for conditional requests;
- streams provider responses through byte/time limits, bounds release/asset
  counts and material fields, and safely reads pre-asset caches as an empty,
  fail-closed asset list;
- parses `v1.2.3` and `1.2.3` tags as semantic versions;
- selects the highest compatible SemVer 2.0 precedence independently of
  provider list order and never uses build metadata as precedence;
- distinguishes available, current, downgrade, ignored, and deferred results;
- serializes the cache and user-suppression values that the host application
  must persist;
- has no Flutter, storage, UI, installer, or platform-plugin dependency.

## Usage

```dart
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:release_update/release_update.dart';

Future<void> checkForUpdate({
  ReleaseCacheEntry? cache,
  UpdateSuppression suppression = const UpdateSuppression.none(),
}) async {
  final client = http.Client();
  try {
    final policy = UpdatePolicy(
      remindLaterDuration: const Duration(hours: 24),
    );
    final checker = ReleaseUpdateChecker(
      source: GitHubReleaseSource(
        client: client,
        owner: 'your-organization',
        repository: 'your-application',
        userAgent: 'your-application/1.0',
      ),
      policy: policy,
    );

    final result = await checker.check(
      currentVersion: Version.parse('1.4.0'),
      cache: cache,
      suppression: suppression,
      // The default automatic reason skips HTTP while a matching cache is
      // less than 24 hours old. Use UpdateCheckReason.manual for a user-
      // initiated "Check now" action.
      reason: UpdateCheckReason.automatic,
    );

    // Persist result.cache.toJson() after every successful check.
    if (result.decision.shouldPrompt) {
      final release = result.decision.latestRelease;
      // Present release.name, release.notes, and release.pageUri.

      // If the user chooses Ignore:
      suppression = policy.ignore(
        state: suppression,
        version: release.version,
      );

      // Or, if the user chooses Later:
      suppression = policy.remindLater(
        state: suppression,
        version: release.version,
        now: DateTime.now(),
      );
      // Persist suppression.toJson().
    }
  } finally {
    client.close();
  }
}
```

`GitHubReleaseSource` does not own or close its injected `http.Client`.
`ReleaseUpdateChecker` only reuses a cache whose `sourceId` matches its source,
preventing an `ETag` from one repository being sent to another.
Applications with platform-specific artifacts should use
`ReleaseCatalogChecker` and `ReleaseCatalogPolicy`; the default catalog is
bounded to 20 provider entries, filters draft/prerelease entries, and has a
separate source identity so an old `/latest` validator cannot cross into the
catalog cache. Non-SemVer release entries and unrelated incomplete/malformed
assets are skipped independently; a matching malformed name/identifier taints
that candidate so it cannot become eligible through a duplicate.
Automatic checks use a 24-hour minimum interval by default; inject
`UpdateCheckSchedule` to change it. Manual checks always contact the source.

## Security and distribution boundary

Public GitHub repositories need no token. Never embed a repository maintainer
token in a distributed application. A private-repository integration should
obtain short-lived user credentials or use a separately secured backend.

This package decides whether to prompt; it does not install an update. The host
application must route the action through its signed distribution channel, such
as Google Play in-app updates, the Microsoft Store, or a notarized macOS
release.
