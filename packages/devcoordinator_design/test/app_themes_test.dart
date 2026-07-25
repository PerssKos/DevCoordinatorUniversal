import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppThemes', () {
    for (final style in VisualStyle.values) {
      test('${style.name} supplies complete light and dark themes', () {
        final themes = AppThemes.forStyle(style);
        final lightTokens = themes.light.appTokens;
        final darkTokens = themes.dark.appTokens;

        expect(themes.light.brightness, Brightness.light);
        expect(themes.dark.brightness, Brightness.dark);
        expect(lightTokens.visualStyle, style);
        expect(darkTokens.visualStyle, style);
        expect(themes.light.colorScheme.primary, lightTokens.accent);
        expect(themes.dark.colorScheme.primary, darkTokens.accent);
        expect(lightTokens.canvas, isNot(darkTokens.canvas));
        expect(lightTokens.textPrimary, isNot(darkTokens.textPrimary));
      });
    }

    test('styles have distinguishable semantic geometry', () {
      final oneUi = AppThemes.light(VisualStyle.oneUiInspired).appTokens;
      final cupertino = AppThemes.light(VisualStyle.cupertino).appTokens;
      final material = AppThemes.light(VisualStyle.material).appTokens;

      expect(<double>{
        oneUi.radiusLarge,
        cupertino.radiusLarge,
        material.radiusLarge,
      }, hasLength(3));
      expect(
        oneUi.navigationBarHeight,
        greaterThan(material.navigationBarHeight),
      );
      expect(
        material.navigationBarHeight,
        greaterThan(cupertino.navigationBarHeight),
      );
    });

    test('theme tokens interpolate colors and dimensions', () {
      final light = AppThemes.light(VisualStyle.oneUiInspired).appTokens;
      final dark = AppThemes.dark(VisualStyle.material).appTokens;
      final midpoint = light.lerp(dark, 0.5);

      expect(midpoint.visualStyle, VisualStyle.material);
      expect(midpoint.radiusLarge, (light.radiusLarge + dark.radiusLarge) / 2);
      expect(midpoint.canvas, Color.lerp(light.canvas, dark.canvas, 0.5));
    });
  });

  testWidgets('active style and brightness can switch independently', (
    tester,
  ) async {
    Future<void> pump({
      required VisualStyle style,
      required ThemeModePreference mode,
    }) async {
      final themes = AppThemes.forStyle(style);
      await tester.pumpWidget(
        MaterialApp(
          theme: themes.light,
          darkTheme: themes.dark,
          themeMode: mode.flutterThemeMode,
          home: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Text(
                '${theme.appTokens.visualStyle.storageValue}'
                ':${theme.brightness.name}',
                textDirection: TextDirection.ltr,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(
      style: VisualStyle.oneUiInspired,
      mode: ThemeModePreference.light,
    );
    expect(find.text('one_ui_inspired:light'), findsOneWidget);

    await pump(style: VisualStyle.cupertino, mode: ThemeModePreference.light);
    expect(find.text('cupertino:light'), findsOneWidget);

    await pump(style: VisualStyle.cupertino, mode: ThemeModePreference.dark);
    expect(find.text('cupertino:dark'), findsOneWidget);
  });
}
