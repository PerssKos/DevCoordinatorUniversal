import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../core/localization/app_strings.dart';
import '../setup/connection_setup_screen.dart';
import 'collection_screens.dart';
import 'native_collection_screens.dart';
import 'overview_screen.dart';
import 'settings_screen.dart';

final class UniversalAppShell extends StatelessWidget {
  const UniversalAppShell({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final strings = AppStrings.of(context);

    if (state.settings.connection == null ||
        (state.inventory == null && state.nativeInventory == null)) {
      return AppScaffold(body: ConnectionSetupScreen(controller: controller));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final destinations = wide
            ? _wideDestinations(strings)
            : _compactDestinations(strings);
        final selectedIndex = wide
            ? _wideIndex(state.section)
            : _compactIndex(state.section);
        final section = state.section == AppSection.more && wide
            ? AppSection.overview
            : state.section;

        return AppScaffold(
          title: _title(strings, section),
          destinations: destinations,
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            controller.selectSection(
              wide ? _wideSection(index) : _compactSection(index),
            );
          },
          actions: <Widget>[
            IconButton(
              tooltip: strings.refresh,
              onPressed: state.canRefresh ? controller.refresh : null,
              icon: state.refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 8),
          ],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (state.hasStaleInventory) ...<Widget>[
                AppCard(
                  key: const ValueKey<String>('stale-inventory-notice'),
                  child: AppStatus(
                    label: strings.text(
                      en: 'Showing the last successful inventory snapshot. It is read-only until refresh succeeds.',
                      ru: 'Показан последний успешный снимок инвентаря. До успешного обновления он доступен только для чтения.',
                    ),
                    tone: AppStatusTone.warning,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (state.lastNativeOperation != null) ...<Widget>[
                _NativeOperationBanner(
                  operation: state.lastNativeOperation!,
                  onDismiss: controller.dismissLastNativeOperation,
                ),
                const SizedBox(height: 12),
              ],
              if (state.connectionError != null) ...<Widget>[
                _MessageBanner(
                  message: state.connectionError!,
                  tone: AppStatusTone.danger,
                  onDismiss: controller.clearMessage,
                ),
                const SizedBox(height: 12),
              ],
              Expanded(child: _screenFor(context, section, compact: !wide)),
            ],
          ),
        );
      },
    );
  }

  Widget _screenFor(
    BuildContext context,
    AppSection section, {
    required bool compact,
  }) {
    final nativeInventory = controller.state.nativeInventory;
    if (nativeInventory != null) {
      return switch (section) {
        AppSection.overview => NativeOverviewScreen(
          controller: controller,
          inventory: nativeInventory,
        ),
        AppSection.projects => NativeProjectsScreen(
          controller: controller,
          inventory: nativeInventory,
        ),
        AppSection.servers => NativeResourcesScreen(
          controller: controller,
          inventory: nativeInventory,
          kind: NativeGatewayResourceKind.server,
        ),
        AppSection.containers => NativeResourcesScreen(
          controller: controller,
          inventory: nativeInventory,
          kind: NativeGatewayResourceKind.container,
        ),
        AppSection.ports => NativePortsScreen(
          controller: controller,
          inventory: nativeInventory,
        ),
        AppSection.events => NativeEventsScreen(controller: controller),
        AppSection.settings => SettingsScreen(controller: controller),
        AppSection.more => MoreScreen(controller: controller),
      };
    }
    final inventory = controller.state.inventory!;
    return switch (section) {
      AppSection.overview => OverviewScreen(
        controller: controller,
        inventory: inventory,
      ),
      AppSection.projects => ProjectsScreen(
        controller: controller,
        inventory: inventory,
      ),
      AppSection.servers => ServersScreen(
        controller: controller,
        inventory: inventory,
      ),
      AppSection.containers => ContainersScreen(
        controller: controller,
        inventory: inventory,
      ),
      AppSection.ports => PortsScreen(
        controller: controller,
        inventory: inventory,
      ),
      AppSection.events => EventsScreen(inventory: inventory),
      AppSection.settings => SettingsScreen(controller: controller),
      AppSection.more => MoreScreen(controller: controller),
    };
  }

  static List<AppNavigationDestination> _wideDestinations(AppStrings strings) {
    return <AppNavigationDestination>[
      AppNavigationDestination(
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard_rounded,
        label: strings.dashboard,
      ),
      AppNavigationDestination(
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder_rounded,
        label: strings.projects,
      ),
      AppNavigationDestination(
        icon: Icons.dns_outlined,
        selectedIcon: Icons.dns_rounded,
        label: strings.servers,
      ),
      AppNavigationDestination(
        icon: Icons.view_in_ar_outlined,
        selectedIcon: Icons.view_in_ar_rounded,
        label: strings.containers,
      ),
      AppNavigationDestination(
        icon: Icons.cable_outlined,
        selectedIcon: Icons.cable_rounded,
        label: strings.ports,
      ),
      AppNavigationDestination(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        label: strings.events,
      ),
      AppNavigationDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: strings.settings,
      ),
    ];
  }

  static List<AppNavigationDestination> _compactDestinations(
    AppStrings strings,
  ) {
    return <AppNavigationDestination>[
      AppNavigationDestination(
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard_rounded,
        label: strings.dashboard,
      ),
      AppNavigationDestination(
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder_rounded,
        label: strings.projects,
      ),
      AppNavigationDestination(
        icon: Icons.dns_outlined,
        selectedIcon: Icons.dns_rounded,
        label: strings.servers,
      ),
      AppNavigationDestination(
        icon: Icons.view_in_ar_outlined,
        selectedIcon: Icons.view_in_ar_rounded,
        label: strings.containers,
      ),
      AppNavigationDestination(
        icon: Icons.more_horiz_rounded,
        label: strings.text(en: 'More', ru: 'Ещё'),
      ),
    ];
  }

  static int _wideIndex(AppSection section) => switch (section) {
    AppSection.overview || AppSection.more => 0,
    AppSection.projects => 1,
    AppSection.servers => 2,
    AppSection.containers => 3,
    AppSection.ports => 4,
    AppSection.events => 5,
    AppSection.settings => 6,
  };

  static int _compactIndex(AppSection section) => switch (section) {
    AppSection.overview => 0,
    AppSection.projects => 1,
    AppSection.servers => 2,
    AppSection.containers => 3,
    AppSection.ports ||
    AppSection.events ||
    AppSection.settings ||
    AppSection.more => 4,
  };

  static AppSection _wideSection(int index) => AppSection.values[index];

  static AppSection _compactSection(int index) => switch (index) {
    0 => AppSection.overview,
    1 => AppSection.projects,
    2 => AppSection.servers,
    3 => AppSection.containers,
    _ => AppSection.more,
  };

  static String _title(AppStrings strings, AppSection section) {
    return switch (section) {
      AppSection.overview => strings.dashboard,
      AppSection.projects => strings.projects,
      AppSection.servers => strings.servers,
      AppSection.containers => strings.containers,
      AppSection.ports => strings.ports,
      AppSection.events => strings.events,
      AppSection.settings => strings.settings,
      AppSection.more => strings.text(en: 'More', ru: 'Ещё'),
    };
  }
}

final class _NativeOperationBanner extends StatelessWidget {
  const _NativeOperationBanner({
    required this.operation,
    required this.onDismiss,
  });

  final NativeGatewayOperation operation;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final label = switch (operation.status) {
      NativeGatewayOperationStatus.succeeded => strings.text(
        en: 'Operation completed successfully.',
        ru: 'Операция успешно завершена.',
      ),
      NativeGatewayOperationStatus.partial => strings.text(
        en: 'Operation completed only partially. Review every target result.',
        ru: 'Операция выполнена частично. Проверьте результат каждой цели.',
      ),
      NativeGatewayOperationStatus.needsAttention => strings.text(
        en: 'Operation needs attention. Its target results were retained.',
        ru: 'Операция требует внимания. Результаты целей сохранены.',
      ),
      NativeGatewayOperationStatus.failed ||
      NativeGatewayOperationStatus.timedOut ||
      NativeGatewayOperationStatus.cancelled => strings.text(
        en: 'Operation did not complete. Review its retained target results.',
        ru: 'Операция не завершена. Проверьте сохранённые результаты целей.',
      ),
      NativeGatewayOperationStatus.queued ||
      NativeGatewayOperationStatus.running => strings.text(
        en: 'Operation is still in progress.',
        ru: 'Операция ещё выполняется.',
      ),
    };
    final tone = operation.isSuccessful
        ? AppStatusTone.success
        : operation.needsAttention ||
              operation.partial ||
              operation.status == NativeGatewayOperationStatus.timedOut
        ? AppStatusTone.warning
        : AppStatusTone.danger;
    return AppCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: AppStatus(label: label, tone: tone),
          ),
          IconButton(
            tooltip: strings.close,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

final class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    required this.tone,
    required this.onDismiss,
  });

  final String message;
  final AppStatusTone tone;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: AppStatus(label: message, tone: tone),
          ),
          IconButton(
            tooltip: AppStrings.of(context).close,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

AppStatusTone statusTone(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('fail') ||
      normalized.contains('unhealthy') ||
      normalized.contains('wrong') ||
      normalized.contains('expired') ||
      normalized.contains('violation')) {
    return AppStatusTone.danger;
  }
  if (normalized.contains('running') ||
      normalized.contains('healthy') ||
      normalized.contains('active') ||
      normalized.contains('verified')) {
    return AppStatusTone.success;
  }
  if (normalized.contains('start') ||
      normalized.contains('stop') ||
      normalized.contains('pending') ||
      normalized.contains('unknown')) {
    return AppStatusTone.warning;
  }
  return AppStatusTone.neutral;
}

String projectName(CoordinatorProject project, AppStrings strings) {
  final displayName = project.displayName.trim();
  return displayName.isEmpty
      ? strings.text(en: 'Unnamed project', ru: 'Проект без названия')
      : displayName;
}
