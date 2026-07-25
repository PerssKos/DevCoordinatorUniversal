import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../appearance_preferences.dart';
import '../theme_tokens.dart';
import 'app_navigation.dart';

/// A style-aware page shell with responsive bottom or rail navigation.
class AppScaffold extends StatelessWidget {
  /// Creates an adaptive application scaffold.
  const AppScaffold({
    required this.body,
    this.title,
    this.leading,
    this.actions = const <Widget>[],
    this.destinations = const <AppNavigationDestination>[],
    this.selectedIndex = 0,
    this.onDestinationSelected,
    this.floatingActionButton,
    this.bodyPadding,
    this.navigationBreakpoint = 840,
    this.extendedNavigationRail = true,
    this.resizeToAvoidBottomInset = true,
    super.key,
  });

  /// Main page content.
  final Widget body;

  /// Optional page title.
  final String? title;

  /// Optional leading app-bar control.
  final Widget? leading;

  /// Optional app-bar actions.
  final List<Widget> actions;

  /// Destinations presented as bottom or rail navigation.
  final List<AppNavigationDestination> destinations;

  /// Currently selected destination.
  final int selectedIndex;

  /// Called when a navigation destination is selected.
  final ValueChanged<int>? onDestinationSelected;

  /// Optional primary floating action.
  final Widget? floatingActionButton;

  /// Main content inset. Uses semantic page tokens when omitted.
  final EdgeInsetsGeometry? bodyPadding;

  /// Width at which bottom navigation becomes a rail.
  final double navigationBreakpoint;

  /// Whether the wide navigation rail displays labels beside icons.
  final bool extendedNavigationRail;

  /// Whether the scaffold should resize for the software keyboard.
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    assert(
      destinations.isEmpty || destinations.length >= 2,
      'Navigation requires at least two destinations.',
    );
    assert(
      destinations.isEmpty || onDestinationSelected != null,
      'Navigation destinations require onDestinationSelected.',
    );
    assert(
      destinations.isEmpty ||
          (selectedIndex >= 0 && selectedIndex < destinations.length),
      'selectedIndex must identify a navigation destination.',
    );
    final tokens = context.appTokens;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            destinations.isNotEmpty &&
            constraints.maxWidth >= navigationBreakpoint;
        final compact = constraints.maxWidth < 600;
        final padding =
            bodyPadding ??
            EdgeInsets.all(
              compact ? tokens.compactPagePadding : tokens.pagePadding,
            );
        final page = _buildPageBody(
          tokens: tokens,
          padding: padding,
          wide: wide,
        );

        if (tokens.visualStyle == VisualStyle.cupertino) {
          return _buildCupertinoScaffold(tokens, page, wide);
        }
        return _buildMaterialScaffold(page, wide);
      },
    );
  }

  Widget _buildPageBody({
    required AppThemeTokens tokens,
    required EdgeInsetsGeometry padding,
    required bool wide,
  }) {
    Widget page = ColoredBox(
      color: tokens.canvas,
      child: Padding(
        padding: padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: tokens.contentMaxWidth),
            child: SizedBox(width: double.infinity, child: body),
          ),
        ),
      ),
    );

    if (wide) {
      page = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppNavigation(
            destinations: destinations,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected!,
            layout: AppNavigationLayout.rail,
            extended: extendedNavigationRail,
          ),
          Expanded(child: page),
        ],
      );
    }

    if (floatingActionButton != null) {
      page = Stack(
        children: <Widget>[
          Positioned.fill(child: page),
          PositionedDirectional(
            end: tokens.pagePadding,
            bottom: tokens.pagePadding,
            child: floatingActionButton!,
          ),
        ],
      );
    }
    return page;
  }

  Widget _buildMaterialScaffold(Widget page, bool wide) {
    final hasAppBar = title != null || leading != null || actions.isNotEmpty;
    final hasBottomNavigation = destinations.isNotEmpty && !wide;
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: !hasAppBar
          ? null
          : AppBar(
              title: title == null ? null : Text(title!),
              leading: leading,
              actions: actions,
            ),
      body: SafeArea(
        top: !hasAppBar,
        bottom: !hasBottomNavigation,
        child: page,
      ),
      bottomNavigationBar: hasBottomNavigation
          ? AppNavigation(
              destinations: destinations,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected!,
              layout: AppNavigationLayout.bottom,
            )
          : null,
    );
  }

  Widget _buildCupertinoScaffold(
    AppThemeTokens tokens,
    Widget page,
    bool wide,
  ) {
    final navigationBar = title == null && leading == null && actions.isEmpty
        ? null
        : CupertinoNavigationBar(
            middle: title == null ? null : Text(title!),
            leading: leading,
            trailing: actions.isEmpty
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: actions),
            backgroundColor: tokens.surface,
            border: Border(
              bottom: BorderSide(color: tokens.outline, width: 0.5),
            ),
          );

    Widget content = page;
    if (destinations.isNotEmpty && !wide) {
      content = Column(
        children: <Widget>[
          Expanded(child: page),
          AppNavigation(
            destinations: destinations,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected!,
            layout: AppNavigationLayout.bottom,
          ),
        ],
      );
    }

    return CupertinoPageScaffold(
      navigationBar: navigationBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      child: SafeArea(
        top: navigationBar == null,
        bottom: destinations.isEmpty || wide,
        child: content,
      ),
    );
  }
}
