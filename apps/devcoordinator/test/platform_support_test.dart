import 'package:devcoordinator/core/platform/platform_support.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy loopback is exposed only on a verified local macOS target', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        PlatformSupport.supportsLegacyLocalConnection,
        isFalse,
        reason: platform.name,
      );
    }

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(PlatformSupport.supportsLegacyLocalConnection, isTrue);
  });
}
