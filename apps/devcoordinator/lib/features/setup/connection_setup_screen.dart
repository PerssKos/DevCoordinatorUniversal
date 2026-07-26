import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../core/coordinator/native_gateway_policy.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/platform_support.dart';
import '../../core/storage/settings_store.dart';

const defaultNativeGatewayUrl = canonicalProductionNativeGatewayUrl;

final class ConnectionSetupScreen extends StatefulWidget {
  const ConnectionSetupScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<ConnectionSetupScreen> createState() => _ConnectionSetupScreenState();
}

final class _ConnectionSetupScreenState extends State<ConnectionSetupScreen> {
  late StoredConnectionKind _kind;
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;
  late final TextEditingController _agentController;
  late final TextEditingController _tokenController;
  bool _obscureToken = true;
  bool _cleaningCredential = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.controller.state.settings.connection;
    _kind =
        saved?.kind ??
        (PlatformSupport.supportsLegacyLocalConnection
            ? StoredConnectionKind.localLegacyV1
            : StoredConnectionKind.nativeGatewayV2);
    _labelController = TextEditingController(
      text: saved?.label ?? PlatformSupport.platformLabel,
    );
    _urlController = TextEditingController(
      text:
          saved?.baseUrl ??
          (_kind == StoredConnectionKind.localLegacyV1
              ? 'http://127.0.0.1:29876'
              : defaultNativeGatewayUrl),
    );
    _agentController = TextEditingController(
      text: saved?.agent ?? 'devcoordinator-app',
    );
    _tokenController = TextEditingController();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    _agentController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    final state = widget.controller.state;
    final local = _kind == StoredConnectionKind.localLegacyV1;
    final revocationPending =
        state.connectionPhase == ConnectionPhase.revoked &&
        state.settings.connection?.kind == StoredConnectionKind.nativeGatewayV2;
    if (!PlatformSupport.supportsLegacyLocalConnection) {
      return _buildNativeOnly(context, strings, tokens);
    }

    return ListView(
      key: const ValueKey<String>('connection-setup'),
      children: <Widget>[
        const SizedBox(height: 20),
        Text(
          strings.appName,
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: tokens.spaceSm),
        Text(
          strings.text(
            en: 'A truthful client for your projects, servers, containers, ports, and events.',
            ru: 'Честный клиент для проектов, серверов, контейнеров, портов и событий.',
          ),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: tokens.textSecondary),
        ),
        SizedBox(height: tokens.spaceXl),
        if (state.settings.credentialCleanupPending) ...<Widget>[
          AppCard(
            raised: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppStatus(
                  label: strings.text(
                    en: 'Saved credential cleanup is pending',
                    ru: 'Ожидается очистка сохранённых учётных данных',
                  ),
                  tone: AppStatusTone.warning,
                ),
                SizedBox(height: tokens.spaceMd),
                Text(
                  strings.text(
                    en: 'A previous disconnect closed the live service and discarded its session token, but deletion of a legacy secure-storage entry was not confirmed. New connections stay blocked until cleanup succeeds.',
                    ru: 'Предыдущее отключение закрыло активный сервис и удалило токен сеанса, но удаление прежней записи из защищённого хранилища не подтверждено. Новые подключения заблокированы до успешной очистки.',
                  ),
                ),
                SizedBox(height: tokens.spaceMd),
                AppButton(
                  label: strings.text(
                    en: 'Retry credential cleanup',
                    ru: 'Повторить очистку',
                  ),
                  loading: _cleaningCredential,
                  onPressed: _cleaningCredential ? null : _retryCleanup,
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.spaceLg),
        ],
        AppCard(
          raised: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                strings.connection,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.spaceMd),
              Wrap(
                spacing: tokens.spaceSm,
                runSpacing: tokens.spaceSm,
                children: <Widget>[
                  AppButton(
                    label: strings.text(
                      en: 'Local desktop',
                      ru: 'Локальный компьютер',
                    ),
                    variant: local
                        ? AppButtonVariant.primary
                        : AppButtonVariant.secondary,
                    onPressed: PlatformSupport.supportsLegacyLocalConnection
                        ? () => _selectKind(
                            StoredConnectionKind.localLegacyV1,
                            'http://127.0.0.1:29876',
                          )
                        : null,
                  ),
                  AppButton(
                    label: strings.text(
                      en: 'Remote gateway',
                      ru: 'Удалённый шлюз',
                    ),
                    variant: local
                        ? AppButtonVariant.secondary
                        : AppButtonVariant.primary,
                    onPressed: () => _selectKind(
                      StoredConnectionKind.nativeGatewayV2,
                      defaultNativeGatewayUrl,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.spaceMd),
              AppStatus(
                label: local
                    ? strings.text(
                        en: 'Only localhost/127.0.0.0/8 is accepted. The host token stays in this app session and never becomes a remote credential.',
                        ru: 'Разрешены только localhost/127.0.0.0/8. Токен хоста остаётся только в текущем сеансе и никогда не становится удалённым ключом.',
                      )
                    : strings.text(
                        en: 'Android and off-host clients require the HTTPS native gateway with user-scoped sign-in.',
                        ru: 'Android и удалённые клиенты требуют HTTPS-шлюз с персональной авторизацией.',
                      ),
                tone: local ? AppStatusTone.info : AppStatusTone.warning,
              ),
              SizedBox(height: tokens.spaceLg),
              TextField(
                controller: _labelController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: strings.text(
                    en: 'Host name',
                    ru: 'Название хоста',
                  ),
                  hintText: strings.text(
                    en: 'Development machine',
                    ru: 'Рабочий компьютер',
                  ),
                ),
              ),
              SizedBox(height: tokens.spaceMd),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: strings.text(en: 'Endpoint URL', ru: 'Адрес API'),
                ),
              ),
              if (local) ...<Widget>[
                SizedBox(height: tokens.spaceMd),
                TextField(
                  controller: _agentController,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: strings.text(
                      en: 'Action attribution',
                      ru: 'Автор операций',
                    ),
                    helperText: strings.text(
                      en: 'Recorded by the coordinator for every mutation.',
                      ru: 'Координатор записывает это имя для каждой операции.',
                    ),
                  ),
                ),
                SizedBox(height: tokens.spaceMd),
                TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  enableSuggestions: false,
                  autocorrect: false,
                  onSubmitted: state.busy ? null : (_) => _connect(),
                  decoration: InputDecoration(
                    labelText: strings.text(
                      en: 'Coordinator token',
                      ru: 'Токен координатора',
                    ),
                    helperText: strings.text(
                      en: 'Kept only in memory until this app process closes.',
                      ru: 'Хранится только в памяти до завершения приложения.',
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscureToken
                          ? strings.text(en: 'Show token', ru: 'Показать токен')
                          : strings.text(en: 'Hide token', ru: 'Скрыть токен'),
                      onPressed: () {
                        setState(() => _obscureToken = !_obscureToken);
                      },
                      icon: Icon(
                        _obscureToken ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
              ],
              if (!local) ...<Widget>[
                SizedBox(height: tokens.spaceLg),
                Text(
                  strings.text(
                    en: 'Sign-in opens in the system browser and returns through the protected app callback. No host-wide token is requested.',
                    ru: 'Вход откроется в системном браузере и вернётся через защищённый callback приложения. Общий токен хоста не требуется.',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
                ),
              ],
              if (state.connectionError != null) ...<Widget>[
                SizedBox(height: tokens.spaceMd),
                AppStatus(
                  label: state.connectionError!,
                  tone: AppStatusTone.danger,
                ),
              ],
              SizedBox(height: tokens.spaceLg),
              AppButton(
                label: state.busy
                    ? strings.loading
                    : revocationPending
                    ? strings.text(
                        en: 'Retry secure sign-out',
                        ru: 'Повторить безопасный выход',
                      )
                    : local
                    ? strings.connect
                    : strings.text(
                        en: 'Sign in securely',
                        ru: 'Безопасный вход',
                      ),
                loading: state.busy,
                expand: true,
                onPressed:
                    !state.busy && !state.settings.credentialCleanupPending
                    ? revocationPending
                          ? widget.controller.disconnect
                          : _connect
                    : null,
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.spaceXl),
      ],
    );
  }

  Widget _buildNativeOnly(
    BuildContext context,
    AppStrings strings,
    AppThemeTokens tokens,
  ) {
    final state = widget.controller.state;
    final revocationPending =
        state.connectionPhase == ConnectionPhase.revoked &&
        state.settings.connection?.kind == StoredConnectionKind.nativeGatewayV2;
    final phaseLabel = switch (state.connectionPhase) {
      ConnectionPhase.launchingBrowser => strings.text(
        en: 'Opening the system browser…',
        ru: 'Открывается системный браузер…',
      ),
      ConnectionPhase.awaitingCallback => strings.text(
        en: 'Complete sign-in in your browser…',
        ru: 'Завершите вход в браузере…',
      ),
      ConnectionPhase.exchangingCode => strings.text(
        en: 'Completing secure sign-in…',
        ru: 'Завершается безопасный вход…',
      ),
      ConnectionPhase.refreshingSession => strings.text(
        en: 'Restoring the secure session…',
        ru: 'Восстанавливается защищённый сеанс…',
      ),
      ConnectionPhase.loadingInventory => strings.text(
        en: 'Loading your authorized resources…',
        ru: 'Загружаются доступные вам ресурсы…',
      ),
      _ => strings.text(
        en: 'Sign in with your DevCoordinator account',
        ru: 'Войдите в аккаунт DevCoordinator',
      ),
    };
    return ListView(
      key: const ValueKey<String>('connection-setup'),
      children: <Widget>[
        const SizedBox(height: 28),
        Text(
          strings.appName,
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: tokens.spaceSm),
        Text(
          strings.text(
            en: 'Projects, services, containers, ports, and events — with the permissions granted to your account.',
            ru: 'Проекты, сервисы, контейнеры, порты и события — в рамках прав вашего аккаунта.',
          ),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: tokens.textSecondary),
        ),
        SizedBox(height: tokens.spaceXl),
        AppCard(
          raised: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(
                Icons.verified_user_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              SizedBox(height: tokens.spaceMd),
              Text(
                phaseLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.spaceSm),
              Text(
                strings.text(
                  en: 'The system browser verifies your identity. The app stores only a rotating refresh credential in protected platform storage.',
                  ru: 'Личность подтверждается в системном браузере. Приложение хранит только обновляемый ключ сеанса в защищённом хранилище устройства.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              SizedBox(height: tokens.spaceMd),
              AppStatus(
                label: defaultNativeGatewayUrl,
                tone: AppStatusTone.info,
              ),
              if (state.connectionError != null) ...<Widget>[
                SizedBox(height: tokens.spaceMd),
                AppStatus(
                  label: state.connectionError!,
                  tone: AppStatusTone.danger,
                ),
              ],
              SizedBox(height: tokens.spaceLg),
              AppButton(
                key: const ValueKey<String>('native-browser-sign-in'),
                label: state.busy
                    ? strings.loading
                    : revocationPending
                    ? strings.text(
                        en: 'Retry secure sign-out',
                        ru: 'Повторить безопасный выход',
                      )
                    : strings.text(
                        en: 'Sign in securely',
                        ru: 'Безопасный вход',
                      ),
                loading: state.busy,
                expand: true,
                onPressed: state.busy
                    ? null
                    : revocationPending
                    ? widget.controller.disconnect
                    : _connectNativeDefault,
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.spaceXl),
      ],
    );
  }

  Future<void> _connectNativeDefault() {
    return widget.controller.connect(
      profile: const StoredConnectionProfile(
        kind: StoredConnectionKind.nativeGatewayV2,
        baseUrl: defaultNativeGatewayUrl,
        label: 'DevCoordinator',
      ),
    );
  }

  void _selectKind(StoredConnectionKind kind, String defaultUrl) {
    setState(() {
      _kind = kind;
      _urlController.text = defaultUrl;
      _tokenController.clear();
    });
    widget.controller.clearMessage();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    await widget.controller.connect(
      profile: StoredConnectionProfile(
        kind: _kind,
        baseUrl: _urlController.text.trim(),
        label: _labelController.text.trim().isEmpty
            ? PlatformSupport.platformLabel
            : _labelController.text.trim(),
        agent: _agentController.text.trim(),
      ),
      credential: _tokenController.text,
    );
    if (mounted && widget.controller.state.isConnected) {
      _tokenController.clear();
    }
  }

  Future<void> _retryCleanup() async {
    setState(() => _cleaningCredential = true);
    await widget.controller.retryCredentialCleanup();
    if (mounted) {
      setState(() => _cleaningCredential = false);
    }
  }
}
