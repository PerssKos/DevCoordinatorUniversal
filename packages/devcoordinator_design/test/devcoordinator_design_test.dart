import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devcoordinator_design/devcoordinator_design.dart';

void main() {
  group('AppearancePreferences', () {
    test('style storage values round-trip', () {
      for (final style in VisualStyle.values) {
        expect(VisualStyle.fromStorage(style.storageValue), style);
      }
      expect(
        VisualStyle.fromStorage('future_style'),
        VisualStyle.oneUiInspired,
      );
    });

    test('theme mode storage values and Flutter modes round-trip', () {
      for (final mode in ThemeModePreference.values) {
        expect(ThemeModePreference.fromStorage(mode.storageValue), mode);
      }

      expect(ThemeModePreference.system.flutterThemeMode, ThemeMode.system);
      expect(ThemeModePreference.light.flutterThemeMode, ThemeMode.light);
      expect(ThemeModePreference.dark.flutterThemeMode, ThemeMode.dark);
    });

    test('brightness policy is independent from visual style', () {
      const preferences = AppearancePreferences(
        visualStyle: VisualStyle.cupertino,
        themeMode: ThemeModePreference.dark,
      );

      expect(
        preferences.themeMode.resolveBrightness(Brightness.light),
        Brightness.dark,
      );
      expect(preferences.visualStyle, VisualStyle.cupertino);

      final changed = preferences.copyWith(
        themeMode: ThemeModePreference.system,
      );
      expect(changed.visualStyle, VisualStyle.cupertino);
      expect(
        changed.themeMode.resolveBrightness(Brightness.light),
        Brightness.light,
      );
    });

    test('JSON is stable and invalid values fall back safely', () {
      const preferences = AppearancePreferences(
        visualStyle: VisualStyle.material,
        themeMode: ThemeModePreference.light,
      );

      expect(AppearancePreferences.fromJson(preferences.toJson()), preferences);
      expect(
        AppearancePreferences.fromJson(const <String, Object?>{
          'visualStyle': 42,
          'themeMode': 'not-a-mode',
        }),
        const AppearancePreferences(),
      );
    });
  });
}
