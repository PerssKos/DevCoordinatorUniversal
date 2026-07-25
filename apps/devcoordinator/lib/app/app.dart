import 'dart:async';

import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:release_update/release_update.dart';

import '../core/localization/app_strings.dart';
import '../features/shell/app_shell.dart';
import 'app_controller.dart';

final class DevCoordinatorApp extends StatefulWidget {
  const DevCoordinatorApp({required this.controller, super.key});

  final AppController controller;

  @override
  State<DevCoordinatorApp> createState() => _DevCoordinatorAppState();
}

final class _DevCoordinatorAppState extends State<DevCoordinatorApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String? _promptedVersion;
  bool _promptScheduled = false;
  bool _promptVisible = false;
  late bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reduceMotion = _platformRequestsReducedMotion();
    widget.controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final appearance = widget.controller.state.appearance;
        final themes = AppThemes.forStyle(appearance.visualStyle);
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => AppStrings.of(context).appName,
          theme: themes.light,
          darkTheme: themes.dark,
          highContrastTheme: AppThemes.highContrastLight(
            appearance.visualStyle,
          ),
          highContrastDarkTheme: AppThemes.highContrastDark(
            appearance.visualStyle,
          ),
          themeMode: appearance.themeMode.flutterThemeMode,
          themeAnimationDuration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 240),
          supportedLocales: const <Locale>[Locale('ru'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: UniversalAppShell(controller: widget.controller),
        );
      },
    );
  }

  void _onControllerChanged() {
    final release = widget.controller.state.availableRelease;
    if (release == null ||
        release.version.toString() == _promptedVersion ||
        _promptScheduled ||
        _promptVisible) {
      return;
    }
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _promptScheduled = false;
      if (!mounted) return;
      final current = widget.controller.state.availableRelease;
      if (current == null || current.version.toString() == _promptedVersion) {
        return;
      }
      final context = _navigatorKey.currentContext;
      if (context == null) return;
      _promptVisible = true;
      final resolution = await _showUpdateDialog(context, current);
      _promptVisible = false;
      if (resolution != null) {
        _promptedVersion = current.version.toString();
      }
      if (mounted) _onControllerChanged();
    });
  }

  Future<_UpdateDialogResolution?> _showUpdateDialog(
    BuildContext context,
    ReleaseInfo release,
  ) {
    final strings = AppStrings.of(context);
    final notes = release.notes.trim();
    _UpdateDialogAction? busyAction;
    _UpdateDialogAction? failedAction;
    String? actionError;
    return showDialog<_UpdateDialogResolution>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final tokens = context.appTokens;

          Future<void> runAction({
            required _UpdateDialogAction action,
            required Future<bool> Function() operation,
            required _UpdateDialogResolution resolution,
          }) async {
            setDialogState(() {
              busyAction = action;
              failedAction = null;
              actionError = null;
            });
            final completed = await operation();
            if (!dialogContext.mounted) return;
            if (completed) {
              Navigator.of(dialogContext).pop(resolution);
              return;
            }
            setDialogState(() {
              busyAction = null;
              failedAction = action;
              final detail = widget.controller.state.updateMessage?.trim();
              final guidance = switch (action) {
                _UpdateDialogAction.open => strings.text(
                  en: 'The configured HTTPS update page could not be opened. Check the default browser and try again.',
                  ru: 'Не удалось открыть настроенную HTTPS-страницу обновления. Проверьте браузер по умолчанию и повторите попытку.',
                ),
                _UpdateDialogAction.ignore => strings.text(
                  en: 'The choice to skip this version could not be saved. Try again.',
                  ru: 'Не удалось сохранить пропуск этой версии. Повторите попытку.',
                ),
                _UpdateDialogAction.defer => strings.text(
                  en: 'The reminder could not be saved. Try again.',
                  ru: 'Не удалось сохранить напоминание. Повторите попытку.',
                ),
              };
              actionError = detail == null || detail.isEmpty
                  ? guidance
                  : '$guidance $detail';
            });
          }

          return AlertDialog(
            title: Text(
              strings.text(
                en: 'DevCoordinator ${release.version} is available',
                ru: 'Доступен DevCoordinator ${release.version}',
              ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppStatus(
                    label: strings.text(
                      en: 'Published ${release.publishedAt.toLocal()}',
                      ru: 'Опубликовано ${release.publishedAt.toLocal()}',
                    ),
                    tone: AppStatusTone.info,
                  ),
                  SizedBox(height: tokens.spaceMd),
                  Flexible(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(
                          tokens.radiusMedium,
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(tokens.spaceMd),
                        child: SelectableText(
                          notes.isEmpty
                              ? strings.text(
                                  en: 'Open the release page for details.',
                                  ru: 'Откройте страницу релиза для подробностей.',
                                )
                              : notes,
                        ),
                      ),
                    ),
                  ),
                  if (actionError != null) ...<Widget>[
                    SizedBox(height: tokens.spaceMd),
                    AppStatus(
                      key: const ValueKey<String>('update-action-error'),
                      label: actionError!,
                      tone: AppStatusTone.danger,
                    ),
                  ],
                  SizedBox(height: tokens.spaceMd),
                  Text(
                    strings.text(
                      en: 'The app will open this build’s configured HTTPS distribution page. It does not download or silently install files.',
                      ru: 'Приложение откроет настроенную HTTPS-страницу распространения этой сборки. Оно не скачивает и не устанавливает файлы незаметно.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              AppButton(
                label: strings.ignoreVersion,
                variant: AppButtonVariant.text,
                loading: busyAction == _UpdateDialogAction.ignore,
                onPressed: busyAction != null
                    ? null
                    : () => runAction(
                        action: _UpdateDialogAction.ignore,
                        operation: widget.controller.ignoreAvailableRelease,
                        resolution: _UpdateDialogResolution.ignored,
                      ),
              ),
              AppButton(
                label: strings.later,
                variant: AppButtonVariant.secondary,
                loading: busyAction == _UpdateDialogAction.defer,
                onPressed: busyAction != null
                    ? null
                    : () => runAction(
                        action: _UpdateDialogAction.defer,
                        operation: widget.controller.deferAvailableRelease,
                        resolution: _UpdateDialogResolution.deferred,
                      ),
              ),
              AppButton(
                label: failedAction == _UpdateDialogAction.open
                    ? strings.retry
                    : strings.update,
                loading: busyAction == _UpdateDialogAction.open,
                onPressed: busyAction != null
                    ? null
                    : () => runAction(
                        action: _UpdateDialogAction.open,
                        operation: widget.controller.openAvailableRelease,
                        resolution: _UpdateDialogResolution.opened,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void didChangeAccessibilityFeatures() {
    final next = _platformRequestsReducedMotion();
    if (next == _reduceMotion || !mounted) return;
    setState(() {
      _reduceMotion = next;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.handleAppResumed());
    }
  }

  bool _platformRequestsReducedMotion() {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations || features.reduceMotion;
  }
}

enum _UpdateDialogResolution { opened, ignored, deferred }

enum _UpdateDialogAction { open, ignore, defer }
