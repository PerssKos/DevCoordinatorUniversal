import 'package:pub_semver/pub_semver.dart';

/// Compares two versions using SemVer 2.0.0 precedence.
///
/// Build metadata is deliberately ignored. This differs from
/// `pub_semver`'s solver-oriented ordering, which uses build identifiers as a
/// tie-breaker.
int compareSemVerPrecedence(Version left, Version right) {
  var comparison = left.major.compareTo(right.major);
  if (comparison != 0) return comparison.sign;

  comparison = left.minor.compareTo(right.minor);
  if (comparison != 0) return comparison.sign;

  comparison = left.patch.compareTo(right.patch);
  if (comparison != 0) return comparison.sign;

  final leftPreRelease = left.preRelease;
  final rightPreRelease = right.preRelease;
  if (leftPreRelease.isEmpty) {
    return rightPreRelease.isEmpty ? 0 : 1;
  }
  if (rightPreRelease.isEmpty) {
    return -1;
  }

  final sharedLength = leftPreRelease.length < rightPreRelease.length
      ? leftPreRelease.length
      : rightPreRelease.length;
  for (var index = 0; index < sharedLength; index += 1) {
    comparison = _comparePreReleaseIdentifier(
      leftPreRelease[index],
      rightPreRelease[index],
    );
    if (comparison != 0) return comparison;
  }
  return leftPreRelease.length.compareTo(rightPreRelease.length).sign;
}

int _comparePreReleaseIdentifier(Object left, Object right) {
  if (left is int) {
    if (right is int) {
      return left.compareTo(right).sign;
    }
    return -1;
  }
  if (right is int) {
    return 1;
  }
  return left.toString().compareTo(right.toString()).sign;
}
