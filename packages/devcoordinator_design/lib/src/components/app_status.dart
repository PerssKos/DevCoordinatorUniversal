import 'package:flutter/material.dart';

import '../theme_tokens.dart';

/// Semantic tone of an [AppStatus].
enum AppStatusTone {
  /// A passive state without positive or negative meaning.
  neutral,

  /// Context or progress information.
  info,

  /// A successful or healthy state.
  success,

  /// A state requiring caution.
  warning,

  /// A failed, unhealthy, or destructive state.
  danger,
}

/// A compact status badge that always pairs color with an icon and text.
class AppStatus extends StatelessWidget {
  /// Creates a semantic status badge.
  const AppStatus({
    required this.label,
    this.tone = AppStatusTone.neutral,
    this.icon,
    this.semanticLabel,
    super.key,
  });

  /// Visible state label.
  final String label;

  /// Semantic tone used for the icon and background.
  final AppStatusTone tone;

  /// Optional icon override.
  final IconData? icon;

  /// Optional accessibility label that replaces [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final foreground = switch (tone) {
      AppStatusTone.neutral => tokens.textSecondary,
      AppStatusTone.info => tokens.info,
      AppStatusTone.success => tokens.success,
      AppStatusTone.warning => tokens.warning,
      AppStatusTone.danger => tokens.danger,
    };
    final resolvedIcon =
        icon ??
        switch (tone) {
          AppStatusTone.neutral => Icons.remove_circle_outline,
          AppStatusTone.info => Icons.info_outline,
          AppStatusTone.success => Icons.check_circle_outline,
          AppStatusTone.warning => Icons.warning_amber_rounded,
          AppStatusTone.danger => Icons.error_outline,
        };

    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
              border: Border.all(color: foreground.withValues(alpha: 0.32)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spaceSm,
                vertical: tokens.spaceXs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(resolvedIcon, size: 16, color: foreground),
                  SizedBox(width: tokens.spaceXs),
                  Flexible(
                    child: Text(
                      label,
                      softWrap: true,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
