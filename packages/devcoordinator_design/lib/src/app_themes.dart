import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'appearance_preferences.dart';
import 'theme_tokens.dart';

/// The light and dark themes for one visual style.
@immutable
class AppThemePair {
  /// Creates a pair of themes.
  const AppThemePair({required this.light, required this.dark});

  /// Theme used for light brightness.
  final ThemeData light;

  /// Theme used for dark brightness.
  final ThemeData dark;
}

/// Builds complete light and dark theme data for every supported visual style.
abstract final class AppThemes {
  /// Builds both brightness variants for [style].
  static AppThemePair forStyle(VisualStyle style, {bool highContrast = false}) {
    return AppThemePair(
      light: highContrast ? highContrastLight(style) : light(style),
      dark: highContrast ? highContrastDark(style) : dark(style),
    );
  }

  /// Builds the light theme for [style].
  static ThemeData light(VisualStyle style) {
    return _build(style, Brightness.light);
  }

  /// Builds the dark theme for [style].
  static ThemeData dark(VisualStyle style) {
    return _build(style, Brightness.dark);
  }

  /// Builds the explicit high-contrast light theme for [style].
  static ThemeData highContrastLight(VisualStyle style) {
    return _build(style, Brightness.light, highContrast: true);
  }

  /// Builds the explicit high-contrast dark theme for [style].
  static ThemeData highContrastDark(VisualStyle style) {
    return _build(style, Brightness.dark, highContrast: true);
  }

  /// Builds the selected [brightness] for [style].
  static ThemeData resolve(
    VisualStyle style,
    Brightness brightness, {
    bool highContrast = false,
  }) {
    if (highContrast) {
      return brightness == Brightness.light
          ? highContrastLight(style)
          : highContrastDark(style);
    }
    return brightness == Brightness.light ? light(style) : dark(style);
  }

  static ThemeData _build(
    VisualStyle style,
    Brightness brightness, {
    bool highContrast = false,
  }) {
    final tokens = _tokens(style, brightness, highContrast: highContrast);
    final seed = switch (style) {
      VisualStyle.oneUiInspired => const Color(0xFF0B74E5),
      VisualStyle.cupertino => const Color(0xFF007AFF),
      VisualStyle.material => const Color(0xFF6750A4),
    };
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: tokens.accent,
          onPrimary: tokens.onAccent,
          secondary: tokens.info,
          onSecondary: tokens.onInfo,
          tertiary: tokens.success,
          onTertiary: tokens.onSuccess,
          surface: tokens.surface,
          onSurface: tokens.textPrimary,
          surfaceContainerLowest: tokens.canvas,
          surfaceContainerLow: tokens.surface,
          surfaceContainer: tokens.surfaceMuted,
          surfaceContainerHigh: tokens.surfaceRaised,
          surfaceContainerHighest: tokens.surfaceRaised,
          onSurfaceVariant: tokens.textSecondary,
          error: tokens.danger,
          onError: tokens.onDanger,
          outline: tokens.outline,
          outlineVariant: tokens.outline,
        );
    final isCupertino = style == VisualStyle.cupertino;
    final isOneUi = style == VisualStyle.oneUiInspired;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusControl),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radiusControl),
      borderSide: BorderSide(color: tokens.outline),
    );
    final focusedInputBorder = inputBorder.copyWith(
      borderSide: BorderSide(color: tokens.accent, width: 2),
    );
    final errorInputBorder = inputBorder.copyWith(
      borderSide: BorderSide(color: tokens.danger),
    );
    final focusedErrorInputBorder = inputBorder.copyWith(
      borderSide: BorderSide(color: tokens.danger, width: 2),
    );
    final disabledForeground = tokens.textSecondary.withValues(alpha: 0.55);
    final disabledSurface = tokens.surfaceMuted.withValues(alpha: 0.72);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      dividerColor: tokens.outline,
      extensions: <ThemeExtension<dynamic>>[tokens],
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: tokens.accent,
        primaryContrastingColor: tokens.onAccent,
        scaffoldBackgroundColor: tokens.canvas,
        barBackgroundColor: tokens.surface,
        textTheme: CupertinoTextThemeData(
          primaryColor: tokens.textPrimary,
          textStyle: TextStyle(color: tokens.textPrimary, fontSize: 17),
          actionTextStyle: TextStyle(color: tokens.accent, fontSize: 17),
          navTitleTextStyle: TextStyle(
            color: tokens.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          navLargeTitleTextStyle: TextStyle(
            color: tokens.textPrimary,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );

    final textTheme = base.textTheme
        .apply(bodyColor: tokens.textPrimary, displayColor: tokens.textPrimary)
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: isOneUi ? 32 : null,
            fontWeight: FontWeight.w700,
            letterSpacing: isOneUi ? -0.5 : null,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontSize: isCupertino ? 17 : null,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: isCupertino ? 15 : null,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: isOneUi ? 1 : 0,
        centerTitle: isCupertino,
        toolbarHeight: isOneUi ? 72 : 56,
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: isOneUi ? 1 : 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          side: isOneUi || isCupertino
              ? BorderSide.none
              : BorderSide(color: tokens.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: tokens.surfaceMuted,
        focusColor: tokens.accent.withValues(alpha: 0.12),
        hoverColor: tokens.accent.withValues(alpha: 0.06),
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.spaceMd,
          vertical: isOneUi ? 18 : 15,
        ),
        labelStyle: TextStyle(color: tokens.textSecondary),
        floatingLabelStyle: TextStyle(
          color: tokens.accent,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: TextStyle(color: tokens.textSecondary),
        hintStyle: TextStyle(color: tokens.textSecondary),
        errorStyle: TextStyle(
          color: tokens.danger,
          fontWeight: FontWeight.w500,
        ),
        iconColor: tokens.textSecondary,
        prefixIconColor: tokens.textSecondary,
        suffixIconColor: tokens.textSecondary,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusedInputBorder,
        errorBorder: errorInputBorder,
        focusedErrorBorder: focusedErrorInputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: disabledForeground),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(
          0xFF000000,
        ).withValues(alpha: brightness == Brightness.dark ? 0.60 : 0.24),
        barrierColor: const Color(
          0xFF000000,
        ).withValues(alpha: highContrast ? 0.72 : 0.54),
        elevation: isOneUi ? 6 : 3,
        iconColor: tokens.accent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: tokens.textPrimary,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: tokens.textSecondary,
        ),
        actionsPadding: EdgeInsets.fromLTRB(
          tokens.spaceMd,
          0,
          tokens.spaceMd,
          tokens.spaceMd,
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isOneUi ? 24 : 20,
          vertical: 24,
        ),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          side: highContrast
              ? BorderSide(color: tokens.outline, width: 2)
              : BorderSide.none,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return disabledSurface;
          }
          if (states.contains(WidgetState.selected)) {
            return tokens.accent;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return disabledForeground;
          }
          return tokens.onAccent;
        }),
        overlayColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => _controlOverlay(tokens, states),
        ),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSmall / 2),
        ),
        side: BorderSide(color: tokens.outline, width: highContrast ? 2 : 1.5),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return disabledForeground;
          }
          if (states.contains(WidgetState.selected)) {
            return tokens.onAccent;
          }
          return tokens.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return disabledSurface;
          }
          if (states.contains(WidgetState.selected)) {
            return tokens.accent;
          }
          return tokens.surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.accent;
          }
          return states.contains(WidgetState.disabled)
              ? disabledForeground
              : tokens.outline;
        }),
        trackOutlineWidth: WidgetStatePropertyAll<double?>(
          highContrast ? 2 : 1,
        ),
        overlayColor: WidgetStateProperty.resolveWith<Color?>(
          (states) => _controlOverlay(tokens, states),
        ),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.disabled)) {
              return disabledForeground;
            }
            if (states.contains(WidgetState.selected)) {
              return tokens.onAccent;
            }
            return tokens.textPrimary;
          }),
          iconColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.disabled)) {
              return disabledForeground;
            }
            if (states.contains(WidgetState.selected)) {
              return tokens.onAccent;
            }
            return tokens.textPrimary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => states.contains(WidgetState.selected)
                ? tokens.accent
                : Colors.transparent,
          ),
          overlayColor: WidgetStateProperty.resolveWith<Color?>(
            (states) => _controlOverlay(tokens, states),
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(Size.square(48)),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(48, isOneUi ? 52 : 46),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(48, isOneUi ? 52 : 46),
          foregroundColor: tokens.textPrimary,
          side: BorderSide(color: tokens.outline),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: tokens.navigationBarHeight,
        elevation: 0,
        backgroundColor: tokens.surface,
        indicatorColor: tokens.accent.withValues(alpha: 0.16),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusControl),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.surface,
        indicatorColor: tokens.accent.withValues(alpha: 0.16),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusControl),
        ),
        minWidth: tokens.navigationRailWidth,
        selectedIconTheme: IconThemeData(color: tokens.accent),
        unselectedIconTheme: IconThemeData(color: tokens.textSecondary),
        selectedLabelTextStyle: TextStyle(
          color: tokens.accent,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: tokens.textSecondary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accent,
        linearTrackColor: tokens.surfaceMuted,
        circularTrackColor: tokens.surfaceMuted,
      ),
      focusColor: tokens.accent.withValues(alpha: 0.18),
      hoverColor: tokens.accent.withValues(alpha: 0.08),
      splashColor: tokens.accent.withValues(alpha: 0.12),
    );
  }

  static Color? _controlOverlay(
    AppThemeTokens tokens,
    Set<WidgetState> states,
  ) {
    if (states.contains(WidgetState.pressed)) {
      return tokens.accent.withValues(alpha: 0.18);
    }
    if (states.contains(WidgetState.focused)) {
      return tokens.accent.withValues(alpha: 0.16);
    }
    if (states.contains(WidgetState.hovered)) {
      return tokens.accent.withValues(alpha: 0.10);
    }
    return null;
  }

  static AppThemeTokens _tokens(
    VisualStyle style,
    Brightness brightness, {
    bool highContrast = false,
  }) {
    final dark = brightness == Brightness.dark;

    final standard = switch (style) {
      VisualStyle.oneUiInspired => AppThemeTokens(
        visualStyle: style,
        canvas: Color(dark ? 0xFF080808 : 0xFFF6F7F9),
        surface: Color(dark ? 0xFF151515 : 0xFFFFFFFF),
        surfaceRaised: Color(dark ? 0xFF202020 : 0xFFFFFFFF),
        surfaceMuted: Color(dark ? 0xFF2A2A2A : 0xFFEFF1F4),
        outline: Color(dark ? 0xFF3D3D3D : 0xFFD8DBE0),
        textPrimary: Color(dark ? 0xFFF5F5F5 : 0xFF171717),
        textSecondary: Color(dark ? 0xFFA8A8A8 : 0xFF62666D),
        accent: Color(dark ? 0xFF5AA9FF : 0xFF0B74E5),
        onAccent: Color(dark ? 0xFF001D35 : 0xFFFFFFFF),
        success: Color(dark ? 0xFF55D988 : 0xFF168447),
        onSuccess: Color(dark ? 0xFF00210E : 0xFFFFFFFF),
        warning: Color(dark ? 0xFFFFC857 : 0xFF9B6200),
        onWarning: Color(dark ? 0xFF2A1900 : 0xFFFFFFFF),
        danger: Color(dark ? 0xFFFF7B79 : 0xFFCC2E2E),
        onDanger: Color(dark ? 0xFF3B0001 : 0xFFFFFFFF),
        info: Color(dark ? 0xFF76B8FF : 0xFF1769AA),
        onInfo: Color(dark ? 0xFF002E52 : 0xFFFFFFFF),
        radiusSmall: 10,
        radiusMedium: 18,
        radiusLarge: 28,
        radiusControl: 16,
        spaceXs: 4,
        spaceSm: 8,
        spaceMd: 16,
        spaceLg: 24,
        spaceXl: 32,
        pagePadding: 24,
        compactPagePadding: 16,
        contentMaxWidth: 1120,
        navigationRailWidth: 88,
        navigationBarHeight: 72,
      ),
      VisualStyle.cupertino => AppThemeTokens(
        visualStyle: style,
        canvas: Color(dark ? 0xFF000000 : 0xFFF2F2F7),
        surface: Color(dark ? 0xFF1C1C1E : 0xFFFFFFFF),
        surfaceRaised: Color(dark ? 0xFF2C2C2E : 0xFFFFFFFF),
        surfaceMuted: Color(dark ? 0xFF2C2C2E : 0xFFE5E5EA),
        outline: Color(dark ? 0xFF38383A : 0xFFC6C6C8),
        textPrimary: Color(dark ? 0xFFFFFFFF : 0xFF000000),
        textSecondary: Color(dark ? 0xFF98989D : 0xFF636366),
        accent: Color(dark ? 0xFF0A84FF : 0xFF007AFF),
        onAccent: const Color(0xFFFFFFFF),
        success: Color(dark ? 0xFF30D158 : 0xFF248A3D),
        onSuccess: Color(dark ? 0xFF001F08 : 0xFFFFFFFF),
        warning: Color(dark ? 0xFFFFD60A : 0xFF9A6700),
        onWarning: Color(dark ? 0xFF241D00 : 0xFFFFFFFF),
        danger: Color(dark ? 0xFFFF453A : 0xFFD70015),
        onDanger: const Color(0xFFFFFFFF),
        info: Color(dark ? 0xFF64D2FF : 0xFF0071A4),
        onInfo: Color(dark ? 0xFF002631 : 0xFFFFFFFF),
        radiusSmall: 6,
        radiusMedium: 10,
        radiusLarge: 14,
        radiusControl: 12,
        spaceXs: 4,
        spaceSm: 8,
        spaceMd: 16,
        spaceLg: 24,
        spaceXl: 32,
        pagePadding: 24,
        compactPagePadding: 16,
        contentMaxWidth: 1040,
        navigationRailWidth: 76,
        navigationBarHeight: 56,
      ),
      VisualStyle.material => AppThemeTokens(
        visualStyle: style,
        canvas: Color(dark ? 0xFF141218 : 0xFFFFF7FF),
        surface: Color(dark ? 0xFF211F26 : 0xFFFFFBFE),
        surfaceRaised: Color(dark ? 0xFF2B2930 : 0xFFFFFFFF),
        surfaceMuted: Color(dark ? 0xFF36333B : 0xFFF2ECF4),
        outline: Color(dark ? 0xFF938F99 : 0xFF79747E),
        textPrimary: Color(dark ? 0xFFE6E1E5 : 0xFF1D1B20),
        textSecondary: Color(dark ? 0xFFCAC4D0 : 0xFF49454F),
        accent: Color(dark ? 0xFFD0BCFF : 0xFF6750A4),
        onAccent: Color(dark ? 0xFF381E72 : 0xFFFFFFFF),
        success: Color(dark ? 0xFF7DDB91 : 0xFF2E7D32),
        onSuccess: Color(dark ? 0xFF003914 : 0xFFFFFFFF),
        warning: Color(dark ? 0xFFFFB95C : 0xFF8A5600),
        onWarning: Color(dark ? 0xFF2D1700 : 0xFFFFFFFF),
        danger: Color(dark ? 0xFFFFB4AB : 0xFFBA1A1A),
        onDanger: Color(dark ? 0xFF690005 : 0xFFFFFFFF),
        info: Color(dark ? 0xFFA9C7FF : 0xFF315DA8),
        onInfo: Color(dark ? 0xFF002F65 : 0xFFFFFFFF),
        radiusSmall: 8,
        radiusMedium: 12,
        radiusLarge: 16,
        radiusControl: 12,
        spaceXs: 4,
        spaceSm: 8,
        spaceMd: 16,
        spaceLg: 24,
        spaceXl: 32,
        pagePadding: 24,
        compactPagePadding: 16,
        contentMaxWidth: 1120,
        navigationRailWidth: 80,
        navigationBarHeight: 64,
      ),
    };

    if (!highContrast) {
      return standard;
    }

    final shared = dark
        ? standard.copyWith(
            isHighContrast: true,
            canvas: const Color(0xFF000000),
            surface: const Color(0xFF080808),
            surfaceRaised: const Color(0xFF111111),
            surfaceMuted: const Color(0xFF1B1B1B),
            outline: const Color(0xFFFFFFFF),
            textPrimary: const Color(0xFFFFFFFF),
            textSecondary: const Color(0xFFE0E0E0),
            success: const Color(0xFF5EE28A),
            onSuccess: const Color(0xFF000000),
            warning: const Color(0xFFFFD36A),
            onWarning: const Color(0xFF000000),
            danger: const Color(0xFFFF8A8A),
            onDanger: const Color(0xFF000000),
            info: const Color(0xFF80C5FF),
            onInfo: const Color(0xFF000000),
          )
        : standard.copyWith(
            isHighContrast: true,
            canvas: const Color(0xFFFFFFFF),
            surface: const Color(0xFFFFFFFF),
            surfaceRaised: const Color(0xFFFFFFFF),
            surfaceMuted: const Color(0xFFF2F2F2),
            outline: const Color(0xFF1F1F1F),
            textPrimary: const Color(0xFF000000),
            textSecondary: const Color(0xFF333333),
            success: const Color(0xFF006B2E),
            onSuccess: const Color(0xFFFFFFFF),
            warning: const Color(0xFF6B4200),
            onWarning: const Color(0xFFFFFFFF),
            danger: const Color(0xFFA50018),
            onDanger: const Color(0xFFFFFFFF),
            info: const Color(0xFF005B93),
            onInfo: const Color(0xFFFFFFFF),
          );

    return switch ((style, dark)) {
      (VisualStyle.oneUiInspired, false) => shared.copyWith(
        accent: const Color(0xFF004A9F),
        onAccent: const Color(0xFFFFFFFF),
      ),
      (VisualStyle.oneUiInspired, true) => shared.copyWith(
        accent: const Color(0xFF73B7FF),
        onAccent: const Color(0xFF000000),
      ),
      (VisualStyle.cupertino, false) => shared.copyWith(
        accent: const Color(0xFF004FAD),
        onAccent: const Color(0xFFFFFFFF),
      ),
      (VisualStyle.cupertino, true) => shared.copyWith(
        accent: const Color(0xFF5CB0FF),
        onAccent: const Color(0xFF000000),
      ),
      (VisualStyle.material, false) => shared.copyWith(
        accent: const Color(0xFF4A277A),
        onAccent: const Color(0xFFFFFFFF),
      ),
      (VisualStyle.material, true) => shared.copyWith(
        accent: const Color(0xFFD8C2FF),
        onAccent: const Color(0xFF000000),
      ),
    };
  }
}
