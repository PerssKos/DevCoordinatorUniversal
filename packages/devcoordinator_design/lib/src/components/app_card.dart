import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../appearance_preferences.dart';
import '../theme_tokens.dart';

/// A style-aware surface for related content and actions.
class AppCard extends StatelessWidget {
  /// Creates an adaptive card.
  const AppCard({
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.semanticLabel,
    this.raised = false,
    super.key,
  });

  /// Content displayed inside the card.
  final Widget child;

  /// Inner spacing. Defaults to the active standard spacing token.
  final EdgeInsetsGeometry? padding;

  /// Space around the card.
  final EdgeInsetsGeometry? margin;

  /// Optional activation callback.
  final VoidCallback? onTap;

  /// Optional accessibility label for the whole card.
  final String? semanticLabel;

  /// Whether to emphasize the card as raised above nearby surfaces.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final resolvedPadding = padding ?? EdgeInsets.all(tokens.spaceMd);
    final radius = BorderRadius.circular(tokens.radiusLarge);

    if (tokens.visualStyle == VisualStyle.cupertino) {
      Widget content = Padding(padding: resolvedPadding, child: child);
      if (onTap != null) {
        content = CupertinoButton(
          padding: EdgeInsets.zero,
          borderRadius: radius,
          onPressed: onTap,
          child: content,
        );
      }

      return Semantics(
        container: true,
        label: semanticLabel,
        button: onTap != null,
        child: Padding(
          padding: margin ?? EdgeInsets.zero,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: raised ? tokens.surfaceRaised : tokens.surface,
              borderRadius: radius,
              border: Border.all(color: tokens.outline, width: 0.5),
              boxShadow: raised
                  ? <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(borderRadius: radius, child: content),
          ),
        ),
      );
    }

    Widget content = Padding(padding: resolvedPadding, child: child);
    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        child: content,
      );
    }

    return Semantics(
      container: true,
      label: semanticLabel,
      button: onTap != null,
      child: Card(
        margin: margin ?? EdgeInsets.zero,
        elevation: raised
            ? (tokens.visualStyle == VisualStyle.oneUiInspired ? 3 : 2)
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: tokens.visualStyle == VisualStyle.material
              ? BorderSide(color: tokens.outline)
              : BorderSide.none,
        ),
        child: content,
      ),
    );
  }
}
