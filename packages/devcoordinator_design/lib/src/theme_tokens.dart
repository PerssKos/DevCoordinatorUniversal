import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'appearance_preferences.dart';

/// Semantic colors and dimensions consumed by DevCoordinator features.
///
/// Tokens describe intent rather than a particular platform palette. Style
/// packs can therefore change without feature widgets knowing how each style
/// is rendered.
@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  /// Creates a complete semantic token set.
  const AppThemeTokens({
    required this.visualStyle,
    this.isHighContrast = false,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.info,
    required this.onInfo,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusControl,
    required this.spaceXs,
    required this.spaceSm,
    required this.spaceMd,
    required this.spaceLg,
    required this.spaceXl,
    required this.pagePadding,
    required this.compactPagePadding,
    required this.contentMaxWidth,
    required this.navigationRailWidth,
    required this.navigationBarHeight,
  });

  /// The style represented by this token set.
  final VisualStyle visualStyle;

  /// Whether this token set is the explicit high-contrast variant.
  ///
  /// High contrast is independent from [visualStyle] and brightness. Feature
  /// widgets should continue to consume semantic colors instead of branching
  /// on this value.
  final bool isHighContrast;

  /// The application background.
  final Color canvas;

  /// The default content surface.
  final Color surface;

  /// A surface raised above the default content plane.
  final Color surfaceRaised;

  /// A subdued surface used for grouping and passive controls.
  final Color surfaceMuted;

  /// Hairlines, borders, and separators.
  final Color outline;

  /// High-emphasis text.
  final Color textPrimary;

  /// Supporting and lower-emphasis text.
  final Color textSecondary;

  /// The primary interactive color.
  final Color accent;

  /// Content rendered on [accent].
  final Color onAccent;

  /// Successful state color.
  final Color success;

  /// Content rendered on [success].
  final Color onSuccess;

  /// Warning state color.
  final Color warning;

  /// Content rendered on [warning].
  final Color onWarning;

  /// Destructive or failed state color.
  final Color danger;

  /// Content rendered on [danger].
  final Color onDanger;

  /// Informational state color.
  final Color info;

  /// Content rendered on [info].
  final Color onInfo;

  /// Radius for compact elements such as badges.
  final double radiusSmall;

  /// Radius for standard surfaces.
  final double radiusMedium;

  /// Radius for prominent containers.
  final double radiusLarge;

  /// Radius for interactive controls.
  final double radiusControl;

  /// Extra-small spacing unit.
  final double spaceXs;

  /// Small spacing unit.
  final double spaceSm;

  /// Standard spacing unit.
  final double spaceMd;

  /// Large spacing unit.
  final double spaceLg;

  /// Extra-large spacing unit.
  final double spaceXl;

  /// Page inset at regular widths.
  final double pagePadding;

  /// Page inset at compact widths.
  final double compactPagePadding;

  /// Recommended maximum width for reading-focused content.
  final double contentMaxWidth;

  /// Width of collapsed adaptive navigation.
  final double navigationRailWidth;

  /// Height of bottom adaptive navigation.
  final double navigationBarHeight;

  @override
  AppThemeTokens copyWith({
    VisualStyle? visualStyle,
    bool? isHighContrast,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? info,
    Color? onInfo,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? radiusControl,
    double? spaceXs,
    double? spaceSm,
    double? spaceMd,
    double? spaceLg,
    double? spaceXl,
    double? pagePadding,
    double? compactPagePadding,
    double? contentMaxWidth,
    double? navigationRailWidth,
    double? navigationBarHeight,
  }) {
    return AppThemeTokens(
      visualStyle: visualStyle ?? this.visualStyle,
      isHighContrast: isHighContrast ?? this.isHighContrast,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      outline: outline ?? this.outline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      radiusControl: radiusControl ?? this.radiusControl,
      spaceXs: spaceXs ?? this.spaceXs,
      spaceSm: spaceSm ?? this.spaceSm,
      spaceMd: spaceMd ?? this.spaceMd,
      spaceLg: spaceLg ?? this.spaceLg,
      spaceXl: spaceXl ?? this.spaceXl,
      pagePadding: pagePadding ?? this.pagePadding,
      compactPagePadding: compactPagePadding ?? this.compactPagePadding,
      contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
      navigationRailWidth: navigationRailWidth ?? this.navigationRailWidth,
      navigationBarHeight: navigationBarHeight ?? this.navigationBarHeight,
    );
  }

  @override
  AppThemeTokens lerp(covariant AppThemeTokens? other, double t) {
    if (other == null) {
      return this;
    }

    double value(double from, double to) => lerpDouble(from, to, t)!;

    return AppThemeTokens(
      visualStyle: t < 0.5 ? visualStyle : other.visualStyle,
      isHighContrast: t < 0.5 ? isHighContrast : other.isHighContrast,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      radiusSmall: value(radiusSmall, other.radiusSmall),
      radiusMedium: value(radiusMedium, other.radiusMedium),
      radiusLarge: value(radiusLarge, other.radiusLarge),
      radiusControl: value(radiusControl, other.radiusControl),
      spaceXs: value(spaceXs, other.spaceXs),
      spaceSm: value(spaceSm, other.spaceSm),
      spaceMd: value(spaceMd, other.spaceMd),
      spaceLg: value(spaceLg, other.spaceLg),
      spaceXl: value(spaceXl, other.spaceXl),
      pagePadding: value(pagePadding, other.pagePadding),
      compactPagePadding: value(compactPagePadding, other.compactPagePadding),
      contentMaxWidth: value(contentMaxWidth, other.contentMaxWidth),
      navigationRailWidth: value(
        navigationRailWidth,
        other.navigationRailWidth,
      ),
      navigationBarHeight: value(
        navigationBarHeight,
        other.navigationBarHeight,
      ),
    );
  }
}

/// Typed access to the required DevCoordinator theme extension.
extension AppThemeDataX on ThemeData {
  /// Semantic tokens installed by the DevCoordinator theme builder.
  AppThemeTokens get appTokens {
    final tokens = extension<AppThemeTokens>();
    if (tokens == null) {
      throw StateError(
        'AppThemeTokens are missing. Use a theme created by AppThemes.',
      );
    }
    return tokens;
  }
}

/// Convenient semantic token lookup from a widget context.
extension AppThemeContextX on BuildContext {
  /// Semantic tokens from the nearest active theme.
  AppThemeTokens get appTokens => Theme.of(this).appTokens;
}
