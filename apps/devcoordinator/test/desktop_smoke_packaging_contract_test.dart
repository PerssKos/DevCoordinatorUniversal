import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS release build explicitly targets both supported architectures',
    () {
      final releaseConfig = _readRepositoryFile(
        'apps/devcoordinator/macos/Runner/Configs/Release.xcconfig',
      );
      final xcodeProject = _readRepositoryFile(
        'apps/devcoordinator/macos/Runner.xcodeproj/project.pbxproj',
      );
      final workflow = _readRepositoryFile('.github/workflows/ci.yml');
      final profileTarget = _xcodeConfigurationBlock(
        xcodeProject,
        id: '338D0CEA231458BD00FA5F75',
        name: 'Profile',
      );
      final releaseTarget = _xcodeConfigurationBlock(
        xcodeProject,
        id: '33CC10FD2044A3C60003C045',
        name: 'Release',
      );
      final debugTarget = _xcodeConfigurationBlock(
        xcodeProject,
        id: '33CC10FC2044A3C60003C045',
        name: 'Debug',
      );

      expect(
        releaseConfig,
        matches(RegExp(r'^ARCHS = x86_64 arm64$', multiLine: true)),
      );
      expect(
        releaseConfig,
        matches(RegExp(r'^ONLY_ACTIVE_ARCH = NO$', multiLine: true)),
      );
      for (final target in <String>[profileTarget, releaseTarget]) {
        expect(target, matches(RegExp(r'ARCHS = \(\s*x86_64,\s*arm64,\s*\);')));
        expect(target, contains('ONLY_ACTIVE_ARCH = NO;'));
      }
      expect(debugTarget, isNot(contains('ARCHS = (')));
      expect(debugTarget, isNot(contains('ONLY_ACTIVE_ARCH = NO;')));
      expect(
        workflow,
        contains(r'''            os: macos-15-intel
            build-arguments: macos --release
            xcode_archs: x86_64 arm64
            xcode_only_active_arch: 'NO'
'''),
      );
      expect(
        workflow,
        contains(r'''          FLUTTER_XCODE_ARCHS: ${{ matrix.xcode_archs }}
          FLUTTER_XCODE_ONLY_ACTIVE_ARCH: ${{ matrix.xcode_only_active_arch }}
'''),
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

String _xcodeConfigurationBlock(
  String project, {
  required String id,
  required String name,
}) {
  final match = RegExp(
    '${RegExp.escape(id)} /\\* ${RegExp.escape(name)} \\*/ = '
    '\\{(.*?)\\n\\t\\t\\};',
    dotAll: true,
  ).firstMatch(project);
  expect(match, isNotNull, reason: 'Missing $name target configuration $id');
  return match!.group(1)!;
}
