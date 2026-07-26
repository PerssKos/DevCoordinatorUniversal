import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android declares one exact custom-scheme OAuth callback', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');

    expect(
      _occurrences(
        manifest,
        'android:scheme="io.github.holyglory.devcoordinator"',
      ),
      1,
    );
    expect(manifest, contains('android:host="oauth"'));
    expect(manifest, contains('android:path="/callback"'));
    expect(
      manifest,
      contains('android:name="android.intent.category.BROWSABLE"'),
    );
    expect(manifest, contains('android:launchMode="singleTop"'));
    expect(manifest, contains('android:name="flutter_deeplinking_enabled"'));
    expect(manifest, contains('android:value="false"'));
  });

  test('macOS registers the exact callback scheme', () {
    final plist = _read('macos/Runner/Info.plist');

    expect(plist, contains('<key>CFBundleURLTypes</key>'));
    expect(
      _occurrences(
        plist,
        '<string>io.github.holyglory.devcoordinator</string>',
      ),
      1,
    );
  });

  test('Windows forwards callbacks and packages protocol activation', () {
    final main = _read('windows/runner/main.cpp');
    final pubspec = _read('pubspec.yaml');

    expect(main, contains('app_links/app_links_plugin_c_api.h'));
    expect(main, contains('SendAppLinkToInstance()'));
    expect(
      pubspec,
      contains('protocol_activation: io.github.holyglory.devcoordinator'),
    );
  });

  test('callback router is initialized before the Flutter tree starts', () {
    final main = _read('lib/main.dart');

    expect(main, contains('PlatformNativeAuthorizationCallbackRouter()'));
    expect(
      main.indexOf('callbackRouter.initialize()'),
      lessThan(main.indexOf('runApp(')),
    );
  });
}

String _read(String packagePath) {
  final candidates = <File>[
    File('apps/devcoordinator/$packagePath'),
    File(packagePath),
  ];
  return candidates.firstWhere((file) => file.existsSync()).readAsStringSync();
}

int _occurrences(String source, String pattern) =>
    pattern.allMatches(source).length;
