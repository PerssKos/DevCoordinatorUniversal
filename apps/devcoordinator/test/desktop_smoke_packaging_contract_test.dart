import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS release build explicitly targets both supported architectures',
    () {
      final releaseConfig = _readRepositoryFile(
        'apps/devcoordinator/macos/Runner/Configs/Release.xcconfig',
      );

      expect(
        releaseConfig,
        matches(RegExp(r'^ARCHS = x86_64 arm64$', multiLine: true)),
      );
      expect(
        releaseConfig,
        matches(RegExp(r'^ONLY_ACTIVE_ARCH = NO$', multiLine: true)),
      );
    },
  );

  test('macOS smoke packaging preserves and rechecks the application bundle', () {
    final workflow = _readRepositoryFile('.github/workflows/ci.yml');
    final packager = _readRepositoryFile('tool/package_macos_smoke.sh');
    final verifier = _readRepositoryFile('tool/verify_macos_smoke_bundle.sh');

    expect(workflow, contains('tool/package_macos_smoke.sh'));
    expect(
      workflow,
      contains('source/apps/devcoordinator/build/smoke/macos/*'),
    );
    expect(
      workflow,
      isNot(
        contains(
          'source/apps/devcoordinator/build/macos/Build/Products/Release/*.app',
        ),
      ),
    );

    for (final required in <String>[
      '/usr/bin/ditto',
      '--sequesterRsrc',
      '--keepParent',
      '/usr/bin/ditto -x -k',
      'write_symlink_manifest',
      'verify_macos_smoke_bundle.sh',
      'macos-universal-adhoc-smoke.zip',
      '/usr/bin/shasum -a 256 -c',
    ]) {
      expect(packager, contains(required), reason: required);
    }

    for (final required in <String>[
      '/usr/bin/codesign',
      '--verify',
      '--deep',
      '--strict',
      'Signature=adhoc',
      '/usr/bin/lipo -verify_arch x86_64 arm64',
      'CFBundleIdentifier',
      'CFBundleShortVersionString',
      'CFBundleVersion',
      'CFBundleURLTypes.0.CFBundleURLSchemes.0',
      'io.github.holyglory.devcoordinator',
      'PerssKos/DevCoordinatorUniversal',
      'https://console.classified.guru/api/v2',
    ]) {
      expect(verifier, contains(required), reason: required);
    }
  });
}

String _readRepositoryFile(String relativePath) {
  final candidates = <File>[File(relativePath), File('../../$relativePath')];
  return candidates.firstWhere((file) => file.existsSync()).readAsStringSync();
}
