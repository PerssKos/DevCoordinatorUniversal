import 'release_models.dart';

/// Controls how often automatic update discovery may contact a source.
final class UpdateCheckSchedule {
  /// Creates an automatic-check schedule.
  UpdateCheckSchedule({this.minimumInterval = const Duration(hours: 24)}) {
    if (minimumInterval <= Duration.zero) {
      throw ArgumentError.value(
        minimumInterval,
        'minimumInterval',
        'Must be positive.',
      );
    }
  }

  /// Minimum time between successful automatic checks.
  final Duration minimumInterval;

  /// Whether a source should be contacted during an automatic check.
  ///
  /// A missing or foreign cache is always due. A backwards wall-clock jump is
  /// also treated as due so an invalid future timestamp cannot suppress checks
  /// indefinitely. Manual checks should bypass this method.
  bool isDue({
    required String sourceId,
    ReleaseCacheEntry? cache,
    DateTime? now,
  }) => isDueSince(
    sourceId: sourceId,
    cachedSourceId: cache?.sourceId,
    validatedAt: cache?.validatedAt,
    now: now,
  );

  /// Whether a source is due using provider-neutral cache identity and time.
  ///
  /// This supports both a single latest release and a bounded release catalog
  /// without coupling the cadence policy to either cache representation.
  bool isDueSince({
    required String sourceId,
    required String? cachedSourceId,
    required DateTime? validatedAt,
    DateTime? now,
  }) {
    if (cachedSourceId != sourceId || validatedAt == null) {
      return true;
    }

    final evaluatedAt = (now ?? DateTime.now()).toUtc();
    final age = evaluatedAt.difference(validatedAt);
    return age.isNegative || age >= minimumInterval;
  }
}
