import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../appearance_preferences.dart';
import '../theme_tokens.dart';

/// Visual emphasis and intent of an [AppButton].
enum AppButtonVariant {
  /// The primary action in the current context.
  primary,

  /// A lower-emphasis alternative action.
  secondary,

  /// An action that can remove data or cause another destructive effect.
  danger,

  /// A compact action without a filled surface.
  text,
}

/// A style-aware button with consistent loading and accessibility behavior.
class AppButton extends StatelessWidget {
  /// Creates an adaptive button.
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.semanticLabel,
    this.loadingSemanticLabel,
    super.key,
  });

  /// Visible action label.
  final String label;

  /// Invoked when the enabled button is activated.
  final VoidCallback? onPressed;

  /// Visual emphasis and action intent.
  final AppButtonVariant variant;

  /// Optional leading icon or other compact visual.
  final Widget? icon;

  /// Whether progress should be shown and activation temporarily disabled.
  final bool loading;

  /// Whether the button should fill the available horizontal space.
  final bool expand;

  /// Optional accessibility label that replaces [label].
  final String? semanticLabel;

  /// Optional accessibility label announced while [loading] is true.
  final String? loadingSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final enabledCallback = loading ? null : onPressed;
    final foreground = switch (variant) {
      AppButtonVariant.primary => tokens.onAccent,
      AppButtonVariant.secondary => tokens.textPrimary,
      AppButtonVariant.danger => tokens.onDanger,
      AppButtonVariant.text => tokens.accent,
    };
    final content = _ButtonContent(
      label: label,
      icon: icon,
      loading: loading,
      cupertino: tokens.visualStyle == VisualStyle.cupertino,
      color: foreground,
      spacing: tokens.spaceSm,
      expand: expand,
    );

    final Widget button;
    if (tokens.visualStyle == VisualStyle.cupertino) {
      final background = switch (variant) {
        AppButtonVariant.primary => tokens.accent,
        AppButtonVariant.secondary => tokens.surfaceMuted,
        AppButtonVariant.danger => tokens.danger,
        AppButtonVariant.text => null,
      };
      button = CupertinoButton(
        onPressed: enabledCallback,
        color: background,
        disabledColor:
            background?.withValues(alpha: 0.45) ?? Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusControl),
        padding: EdgeInsets.symmetric(horizontal: tokens.spaceMd, vertical: 12),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground, size: 20),
            child: content,
          ),
        ),
      );
    } else {
      button = switch (variant) {
        AppButtonVariant.primary => FilledButton(
          onPressed: enabledCallback,
          child: content,
        ),
        AppButtonVariant.secondary => OutlinedButton(
          onPressed: enabledCallback,
          child: content,
        ),
        AppButtonVariant.danger => FilledButton(
          onPressed: enabledCallback,
          style: FilledButton.styleFrom(
            backgroundColor: tokens.danger,
            foregroundColor: tokens.onDanger,
            disabledBackgroundColor: tokens.danger.withValues(alpha: 0.45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusControl),
            ),
          ),
          child: content,
        ),
        AppButtonVariant.text => TextButton(
          onPressed: enabledCallback,
          child: content,
        ),
      };
    }

    return Semantics(
      label: loading
          ? loadingSemanticLabel ?? semanticLabel ?? label
          : semanticLabel ?? label,
      button: true,
      enabled: enabledCallback != null,
      liveRegion: loading,
      child: ExcludeSemantics(
        child: SizedBox(width: expand ? double.infinity : null, child: button),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.loading,
    required this.cupertino,
    required this.color,
    required this.spacing,
    required this.expand,
  });

  final String label;
  final Widget? icon;
  final bool loading;
  final bool cupertino;
  final Color color;
  final double spacing;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget? leading;
    if (!loading) {
      leading = icon;
    } else if (cupertino) {
      leading = CupertinoActivityIndicator(color: color, radius: 9);
    } else {
      leading = SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }

    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (leading != null) ...<Widget>[leading, SizedBox(width: spacing)],
        if (expand)
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          )
        else
          Text(label),
      ],
    );
  }
}
