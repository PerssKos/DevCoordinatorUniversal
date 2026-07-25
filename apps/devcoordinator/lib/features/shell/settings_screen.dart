import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../core/localization/app_strings.dart';
import '../../core/storage/settings_store.dart';

final class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    final state = controller.state;
    final appearance = state.appearance;
    final connection = state.settings.connection!;

    return ListView(
      key: const ValueKey<String>('settings-screen'),
      children: <Widget>[
        _SectionTitle(
          title: strings.appearance,
          subtitle: strings.text(
            en: 'Style and brightness are independent, so every visual language works in light and dark mode.',
            ru: 'Стиль и яркость независимы: каждый вариант работает в светлом и тёмном режиме.',
          ),
        ),
        SizedBox(height: tokens.spaceSm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                strings.style,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.spaceSm),
              Wrap(
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: <Widget>[
                  _AppearanceButton(
                    label: 'One UI',
                    selected:
                        appearance.visualStyle == VisualStyle.oneUiInspired,
                    onPressed: () => _setStyle(VisualStyle.oneUiInspired),
                  ),
                  _AppearanceButton(
                    label: 'iOS / Cupertino',
                    selected: appearance.visualStyle == VisualStyle.cupertino,
                    onPressed: () => _setStyle(VisualStyle.cupertino),
                  ),
                  _AppearanceButton(
                    label: 'Material 3',
                    selected: appearance.visualStyle == VisualStyle.material,
                    onPressed: () => _setStyle(VisualStyle.material),
                  ),
                ],
              ),
              SizedBox(height: tokens.spaceLg),
              Text(
                strings.text(en: 'Brightness', ru: 'Яркость'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SizedBox(height: tokens.spaceSm),
              Wrap(
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: <Widget>[
                  _BrightnessButton(
                    label: strings.system,
                    selected:
                        appearance.themeMode == ThemeModePreference.system,
                    onPressed: () => _setBrightness(ThemeModePreference.system),
                  ),
                  _BrightnessButton(
                    label: strings.light,
                    selected: appearance.themeMode == ThemeModePreference.light,
                    onPressed: () => _setBrightness(ThemeModePreference.light),
                  ),
                  _BrightnessButton(
                    label: strings.dark,
                    selected: appearance.themeMode == ThemeModePreference.dark,
                    onPressed: () => _setBrightness(ThemeModePreference.dark),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.spaceLg),
        _SectionTitle(
          title: strings.connection,
          subtitle: strings.text(
            en: 'The local host token is kept only for the current app session.',
            ru: 'Локальный токен хоста хранится только в текущем сеансе приложения.',
          ),
        ),
        SizedBox(height: tokens.spaceSm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          connection.label,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        SizedBox(height: tokens.spaceXs),
                        SelectableText(
                          connection.baseUrl,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: tokens.textSecondary,
                                fontFamily: 'monospace',
                              ),
                        ),
                      ],
                    ),
                  ),
                  AppStatus(
                    label: state.isConnected
                        ? strings.text(en: 'Connected', ru: 'Подключено')
                        : state.hasStaleInventory
                        ? strings.text(
                            en: 'Snapshot stale',
                            ru: 'Снимок устарел',
                          )
                        : strings.offline,
                    tone: state.isConnected
                        ? AppStatusTone.success
                        : state.hasStaleInventory
                        ? AppStatusTone.warning
                        : AppStatusTone.danger,
                  ),
                ],
              ),
              SizedBox(height: tokens.spaceMd),
              AppStatus(
                label: connection.kind == StoredConnectionKind.localLegacyV1
                    ? strings.text(
                        en: 'Local legacy v1 · loopback only',
                        ru: 'Локальный legacy v1 · только loopback',
                      )
                    : strings.text(
                        en: 'Native gateway v2 · user scoped',
                        ru: 'Нативный шлюз v2 · персональный доступ',
                      ),
                tone: AppStatusTone.info,
              ),
              SizedBox(height: tokens.spaceMd),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: <Widget>[
                  AppButton(
                    label: strings.refresh,
                    variant: AppButtonVariant.secondary,
                    loading: state.refreshing,
                    onPressed: state.canRefresh ? controller.refresh : null,
                  ),
                  AppButton(
                    label: strings.disconnect,
                    variant: AppButtonVariant.danger,
                    onPressed: () => _confirmDisconnect(context),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.spaceLg),
        _SectionTitle(
          title: strings.updates,
          subtitle: strings.text(
            en: 'Checks stable repository releases and opens this build’s configured HTTPS distribution page.',
            ru: 'Проверяет стабильные релизы и открывает настроенную для этой сборки HTTPS-страницу распространения.',
          ),
        ),
        SizedBox(height: tokens.spaceSm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      strings.text(
                        en: 'Automatic checks at launch and foreground',
                        ru: 'Автопроверка при запуске и возврате в приложение',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  AppButton(
                    label: state.settings.updateChecksEnabled
                        ? strings.text(en: 'On', ru: 'Включено')
                        : strings.text(en: 'Off', ru: 'Выключено'),
                    variant: state.settings.updateChecksEnabled
                        ? AppButtonVariant.primary
                        : AppButtonVariant.secondary,
                    onPressed: () => controller.setUpdateChecksEnabled(
                      !state.settings.updateChecksEnabled,
                    ),
                  ),
                ],
              ),
              if (state.updateMessage != null) ...<Widget>[
                SizedBox(height: tokens.spaceMd),
                AppStatus(
                  label: state.updateMessage!,
                  tone: switch (state.updateMessageKind) {
                    UpdateMessageKind.success => AppStatusTone.success,
                    UpdateMessageKind.error => AppStatusTone.danger,
                    UpdateMessageKind.informational ||
                    null => AppStatusTone.info,
                  },
                ),
              ],
              SizedBox(height: tokens.spaceMd),
              AppButton(
                label: strings.checkUpdates,
                variant: AppButtonVariant.secondary,
                loading: state.checkingUpdates,
                expand: true,
                onPressed: state.checkingUpdates
                    ? null
                    : () => controller.checkForUpdates(manual: true),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.spaceLg),
        _SectionTitle(
          title: strings.text(en: 'About', ru: 'О приложении'),
          subtitle: strings.text(
            en: 'Native package with a Flutter-rendered adaptive interface.',
            ru: 'Нативный пакет с адаптивным интерфейсом, который рендерит Flutter.',
          ),
        ),
        SizedBox(height: tokens.spaceSm),
        AppCard(
          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              return Row(
                children: <Widget>[
                  const Icon(Icons.hub_rounded),
                  SizedBox(width: tokens.spaceMd),
                  Expanded(
                    child: Text(
                      info == null
                          ? strings.loading
                          : 'DevCoordinator ${info.version}+${info.buildNumber}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: tokens.spaceXl),
      ],
    );
  }

  Future<void> _setStyle(VisualStyle style) {
    return controller.setAppearance(
      styleName: style.storageValue,
      brightnessName: controller.state.appearance.themeMode.storageValue,
    );
  }

  Future<void> _setBrightness(ThemeModePreference mode) {
    return controller.setAppearance(
      styleName: controller.state.appearance.visualStyle.storageValue,
      brightnessName: mode.storageValue,
    );
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.disconnect),
        content: Text(
          strings.text(
            en: 'Close this connection, forget its saved host details, and discard the session credential?',
            ru: 'Закрыть подключение, забыть сохранённые параметры хоста и удалить токен сеанса?',
          ),
        ),
        actions: <Widget>[
          AppButton(
            label: strings.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            label: strings.disconnect,
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.disconnect();
  }
}

final class _AppearanceButton extends StatelessWidget {
  const _AppearanceButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      variant: selected ? AppButtonVariant.primary : AppButtonVariant.secondary,
      onPressed: onPressed,
    );
  }
}

final class _BrightnessButton extends StatelessWidget {
  const _BrightnessButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      variant: selected ? AppButtonVariant.primary : AppButtonVariant.secondary,
      onPressed: onPressed,
    );
  }
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        SizedBox(height: tokens.spaceXs),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}
