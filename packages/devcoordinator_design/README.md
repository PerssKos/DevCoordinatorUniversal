# devcoordinator_design

The presentation-only design system for DevCoordinator Universal. It provides
three interchangeable visual styles, independent light/dark/system appearance
preferences, semantic tokens, and adaptive widgets shared by Android, macOS,
and Windows.

The `oneUiInspired` and `cupertino` styles are original adaptations for
platform familiarity. They are not Samsung or Apple assets and do not imply
endorsement by either company.

## Appearance model

`VisualStyle` and `ThemeModePreference` are intentionally independent. A user
can choose any visual style and separately choose whether brightness follows
the operating system, stays light, or stays dark.

```dart
const preferences = AppearancePreferences(
  visualStyle: VisualStyle.oneUiInspired,
  themeMode: ThemeModePreference.system,
);

final themes = AppThemes.forStyle(preferences.visualStyle);

MaterialApp(
  theme: themes.light,
  darkTheme: themes.dark,
  themeMode: preferences.themeMode.flutterThemeMode,
  home: const MyHome(),
);
```

Explicit high-contrast variants are available independently of the style and
brightness choice:

```dart
final highContrastThemes = AppThemes.forStyle(
  preferences.visualStyle,
  highContrast: true,
);

final highContrastLight = AppThemes.highContrastLight(
  VisualStyle.oneUiInspired,
);
final highContrastDark = AppThemes.highContrastDark(VisualStyle.cupertino);
```

High-contrast token pairs are verified at WCAG contrast thresholds. The
`AppThemeTokens.isHighContrast` flag lets host applications report the active
mode; feature widgets should still use semantic token roles directly.

`AppearancePreferences.toJson()` and `fromJson()` provide stable storage
values without choosing a persistence library for the application.

## Semantic tokens

Every theme installs `AppThemeTokens` as a `ThemeExtension`. Feature widgets
should consume semantic roles instead of style-specific colors or dimensions:

```dart
final tokens = Theme.of(context).appTokens;
return ColoredBox(color: tokens.surface, child: child);
```

This keeps feature code independent of One UI-inspired, Cupertino, and
Material implementations.

## Adaptive components

- `AppScaffold` switches between bottom navigation and a navigation rail at a
  configurable width.
- `AppNavigation` renders style-appropriate bottom or rail navigation.
- `AppCard`, `AppButton`, and `AppStatus` use the active semantic tokens and
  visual style.

The generated `ThemeData` also tokenizes direct Material `TextField`,
`AlertDialog`, `Checkbox`, `Switch`, and `IconButton` controls. This gives them
the selected visual language while they remain Flutter Material widgets; the
Cupertino style does not turn them into native operating-system controls.

The package must remain presentation-only. It may depend on Flutter, but it
must not import application features, networking, persistence, or domain
packages.
