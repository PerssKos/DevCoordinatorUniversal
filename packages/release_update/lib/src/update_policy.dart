import 'package:pub_semver/pub_semver.dart';

import 'release_models.dart';

/// Persistent user choices that suppress prompts for known release versions.
///
/// Suppression is version-scoped: a release newer than either threshold is
/// eligible immediately, even while an older release is deferred.
final class UpdateSuppression {
  const UpdateSuppression._({
    this.ignoredThroughVersion,
    this.deferredThroughVersion,
    this.deferredUntil,
  });

  /// No prompt suppression.
  const UpdateSuppression.none()
    : ignoredThroughVersion = null,
      deferredThroughVersion = null,
      deferredUntil = null;

  /// Decodes application-persisted suppression state.
  ///
  /// Throws [FormatException] when the version or deferred pair is malformed.
  factory UpdateSuppression.fromJson(Map<String, Object?> json) {
    final ignoredText = _optionalString(json, 'ignoredThroughVersion');
    final deferredText = _optionalString(json, 'deferredThroughVersion');
    final deferredUntilText = _optionalString(json, 'deferredUntil');

    if ((deferredText == null) != (deferredUntilText == null)) {
      throw const FormatException(
        'Deferred version and deadline must both be present or absent.',
      );
    }

    final Version? ignored;
    final Version? deferred;
    final DateTime? deferredUntil;
    try {
      ignored = ignoredText == null ? null : Version.parse(ignoredText);
      deferred = deferredText == null ? null : Version.parse(deferredText);
    } on FormatException catch (error) {
      throw FormatException('Invalid persisted suppression version.', error);
    }

    if (deferredUntilText == null) {
      deferredUntil = null;
    } else {
      deferredUntil = DateTime.tryParse(deferredUntilText)?.toUtc();
      if (deferredUntil == null) {
        throw FormatException(
          'Invalid persisted deferral deadline "$deferredUntilText".',
        );
      }
    }

    return UpdateSuppression._(
      ignoredThroughVersion: ignored,
      deferredThroughVersion: deferred,
      deferredUntil: deferredUntil,
    );
  }

  /// Highest version the user explicitly chose to ignore.
  final Version? ignoredThroughVersion;

  /// Highest version covered by the current temporary deferral.
  final Version? deferredThroughVersion;

  /// UTC instant at which the temporary deferral expires.
  final DateTime? deferredUntil;

  /// Encodes this state for application-owned persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'ignoredThroughVersion': ignoredThroughVersion?.toString(),
    'deferredThroughVersion': deferredThroughVersion?.toString(),
    'deferredUntil': deferredUntil?.toIso8601String(),
  };

  UpdateSuppression _withIgnoredThrough(Version version) {
    final existing = ignoredThroughVersion;
    final threshold =
        existing == null || _compareSemVerPrecedence(existing, version) < 0
        ? version
        : existing;
    final deferred = deferredThroughVersion;
    final shouldClearDeferred =
        deferred != null && _compareSemVerPrecedence(deferred, threshold) <= 0;
    return UpdateSuppression._(
      ignoredThroughVersion: threshold,
      deferredThroughVersion: shouldClearDeferred ? null : deferred,
      deferredUntil: shouldClearDeferred ? null : deferredUntil,
    );
  }

  UpdateSuppression _withDeferral({
    required Version version,
    required DateTime until,
  }) {
    final existingVersion = deferredThroughVersion;
    final existingUntil = deferredUntil;
    if (existingVersion != null &&
        existingUntil != null &&
        _compareSemVerPrecedence(existingVersion, version) > 0) {
      return this;
    }
    final normalizedUntil = until.toUtc();
    final deadline =
        existingVersion != null &&
            existingUntil != null &&
            _compareSemVerPrecedence(existingVersion, version) == 0 &&
            existingUntil.isAfter(normalizedUntil)
        ? existingUntil
        : normalizedUntil;
    return UpdateSuppression._(
      ignoredThroughVersion: ignoredThroughVersion,
      deferredThroughVersion: version,
      deferredUntil: deadline,
    );
  }

  /// Clears temporary deferral while retaining explicit ignore choices.
  UpdateSuppression clearDeferral() =>
      UpdateSuppression._(ignoredThroughVersion: ignoredThroughVersion);

  /// Clears explicit ignore choices while retaining temporary deferral.
  UpdateSuppression clearIgnored() => UpdateSuppression._(
    deferredThroughVersion: deferredThroughVersion,
    deferredUntil: deferredUntil,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateSuppression &&
          ignoredThroughVersion == other.ignoredThroughVersion &&
          deferredThroughVersion == other.deferredThroughVersion &&
          deferredUntil == other.deferredUntil;

  @override
  int get hashCode =>
      Object.hash(ignoredThroughVersion, deferredThroughVersion, deferredUntil);
}

/// Why an update prompt should or should not be shown.
enum UpdateDecisionKind {
  /// A strictly newer, unsuppressed release should be presented.
  updateAvailable,

  /// Installed and remote semantic-version precedence are equal.
  upToDate,

  /// The provider's latest release is older than the installed build.
  remoteOlder,

  /// The user explicitly ignored this release or a newer one.
  ignored,

  /// The user temporarily deferred this release and the deadline is active.
  deferred,
}

/// Pure result of evaluating one installed version against one release.
final class UpdateDecision {
  const UpdateDecision._({
    required this.kind,
    required this.currentVersion,
    required this.latestRelease,
    this.nextPromptAt,
  });

  /// Decision reason.
  final UpdateDecisionKind kind;

  /// Installed semantic version.
  final Version currentVersion;

  /// Provider's current stable release.
  final ReleaseInfo latestRelease;

  /// Deferral deadline for [UpdateDecisionKind.deferred], otherwise null.
  final DateTime? nextPromptAt;

  /// Whether presentation code should ask the user to update.
  bool get shouldPrompt => kind == UpdateDecisionKind.updateAvailable;
}

/// Applies semantic-version precedence and user prompt policy.
final class UpdatePolicy {
  /// Creates a policy.
  ///
  /// [remindLaterDuration] is used by [remindLater] and must be positive.
  UpdatePolicy({this.remindLaterDuration = const Duration(hours: 24)}) {
    if (remindLaterDuration <= Duration.zero) {
      throw ArgumentError.value(
        remindLaterDuration,
        'remindLaterDuration',
        'Must be positive.',
      );
    }
  }

  /// Default duration applied by [remindLater].
  final Duration remindLaterDuration;

  /// Records an explicit choice to ignore [version].
  ///
  /// The threshold never moves backwards. Any obsolete deferral at or below
  /// the ignored threshold is removed.
  UpdateSuppression ignore({
    required UpdateSuppression state,
    required Version version,
  }) => state._withIgnoredThrough(version);

  /// Temporarily defers [version] beginning at [now].
  UpdateSuppression remindLater({
    required UpdateSuppression state,
    required Version version,
    required DateTime now,
  }) => state._withDeferral(
    version: version,
    until: now.toUtc().add(remindLaterDuration),
  );

  /// Evaluates whether [latestRelease] should be presented.
  UpdateDecision evaluate({
    required Version currentVersion,
    required ReleaseInfo latestRelease,
    UpdateSuppression suppression = const UpdateSuppression.none(),
    DateTime? now,
  }) {
    final comparison = _compareSemVerPrecedence(
      latestRelease.version,
      currentVersion,
    );
    if (comparison < 0) {
      return UpdateDecision._(
        kind: UpdateDecisionKind.remoteOlder,
        currentVersion: currentVersion,
        latestRelease: latestRelease,
      );
    }
    if (comparison == 0) {
      return UpdateDecision._(
        kind: UpdateDecisionKind.upToDate,
        currentVersion: currentVersion,
        latestRelease: latestRelease,
      );
    }

    final ignored = suppression.ignoredThroughVersion;
    if (ignored != null &&
        _compareSemVerPrecedence(latestRelease.version, ignored) <= 0) {
      return UpdateDecision._(
        kind: UpdateDecisionKind.ignored,
        currentVersion: currentVersion,
        latestRelease: latestRelease,
      );
    }

    final deferredThrough = suppression.deferredThroughVersion;
    final deferredUntil = suppression.deferredUntil;
    final evaluatedAt = (now ?? DateTime.now()).toUtc();
    if (deferredThrough != null &&
        deferredUntil != null &&
        _compareSemVerPrecedence(latestRelease.version, deferredThrough) <= 0 &&
        evaluatedAt.isBefore(deferredUntil)) {
      return UpdateDecision._(
        kind: UpdateDecisionKind.deferred,
        currentVersion: currentVersion,
        latestRelease: latestRelease,
        nextPromptAt: deferredUntil,
      );
    }

    return UpdateDecision._(
      kind: UpdateDecisionKind.updateAvailable,
      currentVersion: currentVersion,
      latestRelease: latestRelease,
    );
  }
}

int _compareSemVerPrecedence(Version left, Version right) {
  // pub_semver intentionally orders build identifiers for pub's version
  // solver. SemVer 2.0.0 excludes build metadata from precedence, which is
  // the behavior an application update check requires.
  final leftWithoutBuild = Version(
    left.major,
    left.minor,
    left.patch,
    pre: left.preRelease.isEmpty ? null : left.preRelease.join('.'),
  );
  final rightWithoutBuild = Version(
    right.major,
    right.minor,
    right.patch,
    pre: right.preRelease.isEmpty ? null : right.preRelease.join('.'),
  );
  return leftWithoutBuild.compareTo(rightWithoutBuild);
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'Persisted field "$key" must be a non-empty string or null.',
    );
  }
  return value;
}
