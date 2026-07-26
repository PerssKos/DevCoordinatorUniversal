import 'release_models.dart';
import 'semver_precedence.dart';

/// Provider-neutral selection from a bounded stable-release catalog.
final class ReleaseCatalogPolicy {
  /// Creates the pure catalog policy.
  const ReleaseCatalogPolicy();

  /// Selects the highest semantic version overall and for [isEligible].
  ///
  /// Provider ordering and publication timestamps do not override SemVer.
  /// The eligibility callback may enforce platform, distribution-channel, and
  /// artifact provenance rules at the application boundary.
  ReleaseCatalogSelection select({
    required Iterable<ReleaseInfo> releases,
    required bool Function(ReleaseInfo release) isEligible,
  }) {
    final boundedReleases = releases.toList(growable: false);
    for (var left = 0; left < boundedReleases.length; left += 1) {
      for (var right = left + 1; right < boundedReleases.length; right += 1) {
        if (compareSemVerPrecedence(
              boundedReleases[left].version,
              boundedReleases[right].version,
            ) ==
            0) {
          throw ArgumentError.value(
            boundedReleases,
            'releases',
            'Must not contain ambiguous equal-precedence SemVer releases.',
          );
        }
      }
    }

    ReleaseInfo? latestPublished;
    ReleaseInfo? latestCompatible;
    for (final release in boundedReleases) {
      if (latestPublished == null ||
          compareSemVerPrecedence(release.version, latestPublished.version) >
              0) {
        latestPublished = release;
      }
      if (isEligible(release) &&
          (latestCompatible == null ||
              compareSemVerPrecedence(
                    release.version,
                    latestCompatible.version,
                  ) >
                  0)) {
        latestCompatible = release;
      }
    }
    return ReleaseCatalogSelection(
      latestPublished: latestPublished,
      latestCompatible: latestCompatible,
    );
  }
}

/// Highest stable releases selected from one bounded catalog.
final class ReleaseCatalogSelection {
  /// Creates a catalog selection.
  const ReleaseCatalogSelection({
    required this.latestPublished,
    required this.latestCompatible,
  });

  /// Highest semantic version in the bounded catalog.
  final ReleaseInfo? latestPublished;

  /// Highest semantic version accepted by the application eligibility policy.
  final ReleaseInfo? latestCompatible;
}
