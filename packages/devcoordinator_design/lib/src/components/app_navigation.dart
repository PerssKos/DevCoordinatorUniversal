import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../appearance_preferences.dart';
import '../theme_tokens.dart';

/// A destination rendered by [AppNavigation].
@immutable
class AppNavigationDestination {
  /// Creates a navigation destination.
  const AppNavigationDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.tooltip,
  });

  /// Icon used when the destination is not selected.
  final IconData icon;

  /// Icon used when selected, or [icon] when omitted.
  final IconData? selectedIcon;

  /// Visible destination label.
  final String label;

  /// Optional pointer tooltip. Defaults to [label].
  final String? tooltip;
}

/// Geometry used to present adaptive navigation.
enum AppNavigationLayout {
  /// Horizontal navigation at the bottom of a compact window.
  bottom,

  /// Vertical navigation beside content in a wider window.
  rail,
}

/// Style-aware navigation that supports bottom and rail layouts.
class AppNavigation extends StatelessWidget {
  /// Creates adaptive navigation.
  const AppNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.layout,
    this.extended = false,
    super.key,
  }) : assert(destinations.length >= 2),
       assert(selectedIndex >= 0 && selectedIndex < destinations.length);

  /// Available application destinations.
  final List<AppNavigationDestination> destinations;

  /// Index of the currently selected destination.
  final int selectedIndex;

  /// Called when the user selects a destination.
  final ValueChanged<int> onDestinationSelected;

  /// Bottom or rail presentation.
  final AppNavigationLayout layout;

  /// Whether a rail should show full labels beside its icons.
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    if (layout == AppNavigationLayout.bottom) {
      return tokens.visualStyle == VisualStyle.cupertino
          ? _buildCupertinoBottom(tokens)
          : _buildMaterialBottom();
    }

    return tokens.visualStyle == VisualStyle.cupertino
        ? _buildCupertinoRail(tokens)
        : _buildMaterialRail(tokens);
  }

  Widget _buildMaterialBottom() {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: destinations
          .map(
            (destination) => NavigationDestination(
              icon: Tooltip(
                message: destination.tooltip ?? destination.label,
                child: Icon(destination.icon),
              ),
              selectedIcon: Icon(destination.selectedIcon ?? destination.icon),
              label: destination.label,
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildCupertinoBottom(AppThemeTokens tokens) {
    return CupertinoTabBar(
      currentIndex: selectedIndex,
      onTap: onDestinationSelected,
      activeColor: tokens.accent,
      inactiveColor: tokens.textSecondary,
      backgroundColor: tokens.surface,
      border: Border(top: BorderSide(color: tokens.outline, width: 0.5)),
      height: tokens.navigationBarHeight,
      items: destinations
          .map(
            (destination) => BottomNavigationBarItem(
              icon: Tooltip(
                message: destination.tooltip ?? destination.label,
                child: Icon(destination.icon),
              ),
              activeIcon: Icon(destination.selectedIcon ?? destination.icon),
              label: destination.label,
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildMaterialRail(AppThemeTokens tokens) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      extended: extended,
      minWidth: tokens.navigationRailWidth,
      minExtendedWidth: 224,
      labelType: extended ? null : NavigationRailLabelType.all,
      destinations: destinations
          .map(
            (destination) => NavigationRailDestination(
              icon: Tooltip(
                message: destination.tooltip ?? destination.label,
                child: Icon(destination.icon),
              ),
              selectedIcon: Icon(destination.selectedIcon ?? destination.icon),
              label: Text(destination.label),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildCupertinoRail(AppThemeTokens tokens) {
    return SizedBox(
      width: extended ? 224 : tokens.navigationRailWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border(right: BorderSide(color: tokens.outline, width: 0.5)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.spaceSm,
              vertical: tokens.spaceMd,
            ),
            child: Column(
              children: List<Widget>.generate(destinations.length, (index) {
                final destination = destinations[index];
                final selected = index == selectedIndex;
                final foreground = selected
                    ? tokens.accent
                    : tokens.textSecondary;

                return Padding(
                  padding: EdgeInsets.only(bottom: tokens.spaceSm),
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: destination.label,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? tokens.accent.withValues(alpha: 0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          tokens.radiusControl,
                        ),
                      ),
                      child: CupertinoButton(
                        onPressed: () => onDestinationSelected(index),
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.spaceSm,
                          vertical: 12,
                        ),
                        borderRadius: BorderRadius.circular(
                          tokens.radiusControl,
                        ),
                        child: IconTheme(
                          data: IconThemeData(color: foreground, size: 24),
                          child: DefaultTextStyle(
                            style: TextStyle(
                              color: foreground,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            child: Row(
                              mainAxisAlignment: extended
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(
                                  selected
                                      ? destination.selectedIcon ??
                                            destination.icon
                                      : destination.icon,
                                ),
                                if (extended) ...<Widget>[
                                  SizedBox(width: tokens.spaceMd),
                                  Expanded(child: Text(destination.label)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
