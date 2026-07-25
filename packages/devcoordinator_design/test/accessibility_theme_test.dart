import 'dart:math' as math;

import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = <AppNavigationDestination>[
  AppNavigationDestination(icon: Icons.dashboard_outlined, label: 'Overview'),
  AppNavigationDestination(icon: Icons.settings_outlined, label: 'Settings'),
];

void main() {
  group('high-contrast themes', () {
    for (final style in VisualStyle.values) {
      for (final brightness in Brightness.values) {
        test(
          '${style.name}/${brightness.name} satisfies semantic contrast',
          () {
            final theme = AppThemes.resolve(
              style,
              brightness,
              highContrast: true,
            );
            final tokens = theme.appTokens;
            final surfaces = <String, Color>{
              'canvas': tokens.canvas,
              'surface': tokens.surface,
              'surfaceRaised': tokens.surfaceRaised,
              'surfaceMuted': tokens.surfaceMuted,
            };

            expect(theme.brightness, brightness);
            expect(tokens.visualStyle, style);
            expect(tokens.isHighContrast, isTrue);
            for (final surface in surfaces.entries) {
              _expectContrast(
                tokens.textPrimary,
                surface.value,
                atLeast: 7,
                reason: 'textPrimary/${surface.key}',
              );
              _expectContrast(
                tokens.textSecondary,
                surface.value,
                atLeast: 7,
                reason: 'textSecondary/${surface.key}',
              );
            }
            _expectContrast(
              tokens.accent,
              tokens.onAccent,
              atLeast: 7,
              reason: 'accent/onAccent',
            );
            _expectContrast(
              tokens.success,
              tokens.onSuccess,
              atLeast: 4.5,
              reason: 'success/onSuccess',
            );
            _expectContrast(
              tokens.warning,
              tokens.onWarning,
              atLeast: 4.5,
              reason: 'warning/onWarning',
            );
            _expectContrast(
              tokens.danger,
              tokens.onDanger,
              atLeast: 4.5,
              reason: 'danger/onDanger',
            );
            _expectContrast(
              tokens.info,
              tokens.onInfo,
              atLeast: 4.5,
              reason: 'info/onInfo',
            );
          },
        );
      }
    }

    test('high contrast remains independent from style and brightness', () {
      for (final style in VisualStyle.values) {
        final pair = AppThemes.forStyle(style, highContrast: true);
        expect(pair.light.brightness, Brightness.light);
        expect(pair.dark.brightness, Brightness.dark);
        expect(pair.light.appTokens.isHighContrast, isTrue);
        expect(pair.dark.appTokens.isHighContrast, isTrue);
        expect(
          pair.light.appTokens.accent,
          AppThemes.highContrastLight(style).appTokens.accent,
        );
        expect(
          pair.dark.appTokens.accent,
          AppThemes.highContrastDark(style).appTokens.accent,
        );
      }
    });
  });

  group('direct Material control themes', () {
    for (final style in VisualStyle.values) {
      for (final brightness in Brightness.values) {
        for (final highContrast in <bool>[false, true]) {
          test('${style.name}/${brightness.name}/highContrast=$highContrast '
              'uses semantic tokens', () {
            final theme = AppThemes.resolve(
              style,
              brightness,
              highContrast: highContrast,
            );
            final tokens = theme.appTokens;
            final selected = <WidgetState>{WidgetState.selected};
            final idle = <WidgetState>{};

            expect(tokens.isHighContrast, highContrast);
            expect(theme.inputDecorationTheme.filled, isTrue);
            expect(theme.inputDecorationTheme.fillColor, tokens.surfaceMuted);
            expect(
              theme.inputDecorationTheme.focusedBorder,
              isA<OutlineInputBorder>()
                  .having(
                    (border) => border.borderRadius.topLeft.x,
                    'radius',
                    tokens.radiusControl,
                  )
                  .having(
                    (border) => border.borderSide.color,
                    'color',
                    tokens.accent,
                  ),
            );
            expect(theme.dialogTheme.backgroundColor, tokens.surfaceRaised);
            expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
            expect(
              (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
              BorderRadius.circular(tokens.radiusLarge),
            );
            expect(
              theme.checkboxTheme.fillColor!.resolve(selected),
              tokens.accent,
            );
            expect(
              theme.checkboxTheme.checkColor!.resolve(selected),
              tokens.onAccent,
            );
            expect(
              theme.switchTheme.trackColor!.resolve(selected),
              tokens.accent,
            );
            expect(
              theme.switchTheme.thumbColor!.resolve(selected),
              tokens.onAccent,
            );
            expect(
              theme.switchTheme.trackColor!.resolve(idle),
              tokens.surfaceMuted,
            );
            expect(
              theme.iconButtonTheme.style!.iconColor!.resolve(idle),
              tokens.textPrimary,
            );
            expect(
              theme.iconButtonTheme.style!.iconColor!.resolve(selected),
              tokens.onAccent,
            );
            expect(
              theme.iconButtonTheme.style!.backgroundColor!.resolve(selected),
              tokens.accent,
            );
          });
        }
      }
    }
  });

  testWidgets(
    'direct controls and design components render in every theme variant',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      for (final style in VisualStyle.values) {
        for (final brightness in Brightness.values) {
          for (final highContrast in <bool>[false, true]) {
            final theme = AppThemes.resolve(
              style,
              brightness,
              highContrast: highContrast,
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: AppScaffold(
                  title: 'Controls',
                  destinations: _destinations,
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  body: ListView(
                    children: <Widget>[
                      const TextField(
                        decoration: InputDecoration(
                          labelText: 'Project',
                          hintText: 'Choose a project',
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                      ),
                      Checkbox(value: true, onChanged: (_) {}),
                      Switch(value: true, onChanged: (_) {}),
                      IconButton(
                        isSelected: true,
                        onPressed: () {},
                        icon: const Icon(Icons.refresh),
                      ),
                      const AlertDialog(
                        title: Text('Confirm action'),
                        content: Text(
                          'Review the operation before continuing.',
                        ),
                        actions: <Widget>[
                          TextButton(onPressed: null, child: Text('OK')),
                        ],
                      ),
                      AppCard(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const AppStatus(
                              label: 'Ready',
                              tone: AppStatusTone.success,
                            ),
                            AppButton(label: 'Run', onPressed: () {}),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pump();

            expect(
              tester.takeException(),
              isNull,
              reason:
                  '${style.name}/${brightness.name}/'
                  'highContrast=$highContrast',
            );
            expect(find.byType(TextField), findsOneWidget);
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(find.byType(AppCard), findsOneWidget);
            expect(find.byType(AppNavigation), findsOneWidget);
          }
        }
      }
    },
  );
}

void _expectContrast(
  Color foreground,
  Color background, {
  required double atLeast,
  required String reason,
}) {
  expect(
    _contrastRatio(foreground, background),
    greaterThanOrEqualTo(atLeast),
    reason: reason,
  );
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = _relativeLuminance(first);
  final secondLuminance = _relativeLuminance(second);
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double linearize(double component) {
    return component <= 0.04045
        ? component / 12.92
        : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
}
