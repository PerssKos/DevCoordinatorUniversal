import 'package:pub_semver/pub_semver.dart';

import 'release_models.dart';
import 'release_source.dart';
import 'update_policy.dart';
import 'update_schedule.dart';

/// Coordinates conditional fetching, cache validation, and prompt policy.
final class ReleaseUpdateChecker {
  /// Creates a checker.
  ReleaseUpdateChecker({
    required this.source,
    UpdatePolicy? policy,
    UpdateCheckSchedule? schedule,
  }) : policy = policy ?? UpdatePolicy(),
       schedule = schedule ?? UpdateCheckSchedule();

  /// Remote release provider.
  final ReleaseSource source;

  /// Pure decision policy.
  final UpdatePolicy policy;

  /// Automatic-check cadence.
  final UpdateCheckSchedule schedule;

  /// Whether an automatic check should make a network request now.
  ///
  /// Manual checks should call [check] directly.
  bool isAutomaticCheckDue({ReleaseCacheEntry? cache, DateTime? now}) =>
      schedule.isDue(sourceId: source.sourceId, cache: cache, now: now);

  /// Checks for an update and returns both the decision and refreshed cache.
  ///
  /// A [cache] from another [ReleaseSource.sourceId] is deliberately ignored.
  /// Automatic checks reuse matching cache data until [schedule] says it is
  /// due; manual checks always contact [source].
  /// Throws [ReleaseCacheMissException] if the source returns `304` without
  /// matching cached metadata.
  Future<UpdateCheckResult> check({
    required Version currentVersion,
    ReleaseCacheEntry? cache,
    UpdateSuppression suppression = const UpdateSuppression.none(),
    UpdateCheckReason reason = UpdateCheckReason.automatic,
    DateTime? now,
  }) async {
    final checkedAt = (now ?? DateTime.now()).toUtc();
    final matchingCache = cache?.sourceId == source.sourceId ? cache : null;
    if (reason == UpdateCheckReason.automatic &&
        !schedule.isDue(
          sourceId: source.sourceId,
          cache: matchingCache,
          now: checkedAt,
        )) {
      final decision = policy.evaluate(
        currentVersion: currentVersion,
        latestRelease: matchingCache!.release,
        suppression: suppression,
        now: checkedAt,
      );
      return UpdateCheckResult(
        decision: decision,
        cache: matchingCache,
        status: UpdateCheckStatus.skippedFreshCache,
      );
    }

    final response = await source.fetchLatest(ifNoneMatch: matchingCache?.etag);

    final ReleaseCacheEntry refreshedCache;
    final UpdateCheckStatus status;
    switch (response) {
      case ReleaseFetched(:final release, :final etag):
        refreshedCache = ReleaseCacheEntry(
          sourceId: source.sourceId,
          release: release,
          etag: etag,
          validatedAt: checkedAt,
        );
        status = UpdateCheckStatus.fetched;
      case ReleaseNotModified(:final etag):
        if (matchingCache == null) {
          throw const ReleaseCacheMissException(
            'The release source returned 304 without matching cached metadata.',
          );
        }
        refreshedCache = ReleaseCacheEntry(
          sourceId: source.sourceId,
          release: matchingCache.release,
          etag: etag ?? matchingCache.etag,
          validatedAt: checkedAt,
        );
        status = UpdateCheckStatus.notModified;
    }

    final decision = policy.evaluate(
      currentVersion: currentVersion,
      latestRelease: refreshedCache.release,
      suppression: suppression,
      now: checkedAt,
    );
    return UpdateCheckResult(
      decision: decision,
      cache: refreshedCache,
      status: status,
    );
  }
}

/// Why an update check was requested.
enum UpdateCheckReason {
  /// A lifecycle/background check that should respect [UpdateCheckSchedule].
  automatic,

  /// An explicit user action that must always contact the source.
  manual,
}

/// How a successful check obtained its release metadata.
enum UpdateCheckStatus {
  /// A fresh cache made an automatic network request unnecessary.
  skippedFreshCache,

  /// The source returned fresh metadata.
  fetched,

  /// The source returned `304` and the cached release was reused.
  notModified,
}

/// Successful end-to-end update check.
final class UpdateCheckResult {
  /// Creates a result.
  const UpdateCheckResult({
    required this.decision,
    required this.cache,
    required this.status,
  });

  /// Prompt decision.
  final UpdateDecision decision;

  /// Cache entry the application should persist for the next check.
  final ReleaseCacheEntry cache;

  /// How release metadata was obtained.
  final UpdateCheckStatus status;

  /// Whether this check contacted the source.
  bool get networkChecked => status != UpdateCheckStatus.skippedFreshCache;

  /// Whether cached release metadata was reused.
  bool get usedCachedRelease => status != UpdateCheckStatus.fetched;
}
