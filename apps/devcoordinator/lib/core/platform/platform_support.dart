import 'package:flutter/foundation.dart';

final class PlatformSupport {
  const PlatformSupport._();

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// Whether this target can use the current loopback-only coordinator.
  ///
  /// The canonical coordinator has a verified local macOS mode. A Windows
  /// host authority has not been designed, so Windows uses native gateway v2
  /// rather than pretending a loopback service exists.
  static bool get supportsLegacyLocalConnection =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static String get platformLabel => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}
