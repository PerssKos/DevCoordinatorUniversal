import 'package:flutter/material.dart' show Brightness, ThemeMode;

/// The visual language used by adaptive DevCoordinator components.
enum VisualStyle {
  /// A spacious, rounded visual language inspired by contemporary One UI.
  oneUiInspired('one_ui_inspired'),

  /// A visual language that follows familiar Apple platform conventions.
  cupertino('cupertino'),

  /// Flutter's Material 3 visual language.
  material('material');

  const VisualStyle(this.storageValue);

  /// Stable value suitable for preferences storage and synchronization.
  final String storageValue;

  /// Decodes a stored value and safely falls back for unknown future values.
  static VisualStyle fromStorage(
    String? value, {
    VisualStyle fallback = VisualStyle.oneUiInspired,
  }) {
    for (final style in values) {
      if (style.storageValue == value) {
        return style;
      }
    }
    return fallback;
  }
}

/// The brightness policy selected by the user.
enum ThemeModePreference {
  /// Follow the operating system brightness.
  system('system'),

  /// Always use the light theme.
  light('light'),

  /// Always use the dark theme.
  dark('dark');

  const ThemeModePreference(this.storageValue);

  /// Stable value suitable for preferences storage and synchronization.
  final String storageValue;

  /// The matching Flutter theme mode.
  ThemeMode get flutterThemeMode => switch (this) {
    ThemeModePreference.system => ThemeMode.system,
    ThemeModePreference.light => ThemeMode.light,
    ThemeModePreference.dark => ThemeMode.dark,
  };

  /// Resolves this policy for a known operating system brightness.
  Brightness resolveBrightness(Brightness platformBrightness) => switch (this) {
    ThemeModePreference.system => platformBrightness,
    ThemeModePreference.light => Brightness.light,
    ThemeModePreference.dark => Brightness.dark,
  };

  /// Decodes a stored value and safely falls back for unknown future values.
  static ThemeModePreference fromStorage(
    String? value, {
    ThemeModePreference fallback = ThemeModePreference.system,
  }) {
    for (final mode in values) {
      if (mode.storageValue == value) {
        return mode;
      }
    }
    return fallback;
  }
}

/// Persistence-neutral appearance preferences.
///
/// The application owns storage. This value object only defines stable
/// serialization so a feature can change storage backends without changing the
/// design package.
class AppearancePreferences {
  /// Creates appearance preferences.
  const AppearancePreferences({
    this.visualStyle = VisualStyle.oneUiInspired,
    this.themeMode = ThemeModePreference.system,
  });

  /// Creates preferences from a storage or synchronization payload.
  factory AppearancePreferences.fromJson(Map<String, Object?> json) {
    final storedStyle = json['visualStyle'];
    final storedThemeMode = json['themeMode'];
    return AppearancePreferences(
      visualStyle: VisualStyle.fromStorage(
        storedStyle is String ? storedStyle : null,
      ),
      themeMode: ThemeModePreference.fromStorage(
        storedThemeMode is String ? storedThemeMode : null,
      ),
    );
  }

  /// The selected component and theme language.
  final VisualStyle visualStyle;

  /// The independently selected brightness policy.
  final ThemeModePreference themeMode;

  /// Returns a new value with selected fields replaced.
  AppearancePreferences copyWith({
    VisualStyle? visualStyle,
    ThemeModePreference? themeMode,
  }) {
    return AppearancePreferences(
      visualStyle: visualStyle ?? this.visualStyle,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  /// Encodes stable values without binding to a persistence implementation.
  Map<String, String> toJson() => <String, String>{
    'visualStyle': visualStyle.storageValue,
    'themeMode': themeMode.storageValue,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppearancePreferences &&
            other.visualStyle == visualStyle &&
            other.themeMode == themeMode;
  }

  @override
  int get hashCode => Object.hash(visualStyle, themeMode);

  @override
  String toString() {
    return 'AppearancePreferences('
        'visualStyle: $visualStyle, themeMode: $themeMode)';
  }
}
