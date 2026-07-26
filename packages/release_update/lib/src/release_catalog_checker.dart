import 'release_limits.dart';
import 'release_models.dart';
import 'release_source.dart';
import 'update_checker.dart';
import 'update_schedule.dart';

/// Coordinates bounded stable-release discovery and conditional caching.
///
/// This layer intentionally does not know which platform, installer, or asset
/// name an application accepts. The host applies that eligibility policy to
/// [ReleaseCatalogCheckResult.cache].
final class ReleaseCatalogChecker {
  /// Creates a catalog checker.
  ReleaseCatalogChecker({required this.source, UpdateCheckSchedule? schedule})
    : schedule = schedule ?? UpdateCheckSchedule() {
    final maximum = source.maximumCatalogSize;
    if (maximum < 1 || maximum > maximumReleaseCatalogEntries) {
      throw ArgumentError.value(
        maximum,
        'source.maximumCatalogSize',
        'Must be between 1 and $maximumReleaseCatalogEntries.',
      );
    }
    _maximumCatalogSize = maximum;
  }

  /// Remote stable-release catalog.
  final StableReleaseCatalogSource source;

  /// Automatic-check cadence.
  final UpdateCheckSchedule schedule;

  late final int _maximumCatalogSize;

  /// Fetches or revalidates a bounded stable-release catalog.
  Future<ReleaseCatalogCheckResult> check({
    ReleaseCatalogCacheEntry? cache,
    UpdateCheckReason reason = UpdateCheckReason.automatic,
    DateTime? now,
  }) async {
    final checkedAt = (now ?? DateTime.now()).toUtc();
    final matchingCache = cache?.sourceId == source.catalogSourceId
        ? cache
        : null;
    _validateCatalogSize(
      matchingCache?.releases,
      label: 'matching cached release catalog',
    );
    if (reason == UpdateCheckReason.automatic &&
        !schedule.isDueSince(
          sourceId: source.catalogSourceId,
          cachedSourceId: matchingCache?.sourceId,
          validatedAt: matchingCache?.validatedAt,
          now: checkedAt,
        )) {
      return ReleaseCatalogCheckResult(
        cache: matchingCache!,
        status: UpdateCheckStatus.skippedFreshCache,
      );
    }

    final response = await source.fetchStableReleases(
      ifNoneMatch: matchingCache?.etag,
    );
    final ReleaseCatalogCacheEntry refreshedCache;
    final UpdateCheckStatus status;
    switch (response) {
      case ReleaseCatalogFetched(:final releases, :final etag):
        _validateCatalogSize(releases, label: 'fetched release catalog');
        refreshedCache = ReleaseCatalogCacheEntry(
          sourceId: source.catalogSourceId,
          releases: releases,
          etag: etag,
          validatedAt: checkedAt,
        );
        status = UpdateCheckStatus.fetched;
      case ReleaseCatalogNotModified(:final etag):
        if (matchingCache == null) {
          throw const ReleaseCacheMissException(
            'The release catalog returned 304 without matching cached '
            'metadata.',
          );
        }
        refreshedCache = ReleaseCatalogCacheEntry(
          sourceId: source.catalogSourceId,
          releases: matchingCache.releases,
          etag: etag ?? matchingCache.etag,
          validatedAt: checkedAt,
        );
        status = UpdateCheckStatus.notModified;
    }

    return ReleaseCatalogCheckResult(cache: refreshedCache, status: status);
  }

  void _validateCatalogSize(
    List<ReleaseInfo>? releases, {
    required String label,
  }) {
    if (releases != null && releases.length > _maximumCatalogSize) {
      throw ReleaseCatalogBoundsException(
        'The $label contains ${releases.length} entries, exceeding the '
        'source bound of $_maximumCatalogSize.',
      );
    }
  }
}

/// Successful bounded stable-release catalog check.
final class ReleaseCatalogCheckResult {
  /// Creates a result.
  const ReleaseCatalogCheckResult({required this.cache, required this.status});

  /// Catalog entry the application should persist for the next check.
  final ReleaseCatalogCacheEntry cache;

  /// How release metadata was obtained.
  final UpdateCheckStatus status;

  /// Whether this check contacted the source.
  bool get networkChecked => status != UpdateCheckStatus.skippedFreshCache;

  /// Whether cached catalog metadata was reused.
  bool get usedCachedCatalog => status != UpdateCheckStatus.fetched;
}
