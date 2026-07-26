import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_services.dart';
import '../../core/localization/app_strings.dart';
import 'app_shell.dart';

final class NativeOverviewScreen extends StatelessWidget {
  const NativeOverviewScreen({
    required this.controller,
    required this.inventory,
    super.key,
  });

  final AppController controller;
  final NativeGatewayInventory inventory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final session = controller.state.nativeSession;
    return ListView(
      key: const ValueKey<String>('native-overview'),
      children: <Widget>[
        Text(
          strings.text(
            en: 'Authorized workspace',
            ru: 'Доступное рабочее пространство',
          ),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        if (session != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.displayName?.trim().isNotEmpty ?? false
                      ? session.displayName!
                      : session.email,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                AppStatus(
                  label: strings.text(
                    en: '${session.scopes.length} session scopes',
                    ru: 'Прав сеанса: ${session.scopes.length}',
                  ),
                  tone: AppStatusTone.info,
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _MetricCard(
              label: strings.projects,
              value: inventory.projects.length,
            ),
            _MetricCard(
              label: strings.text(en: 'Resources', ru: 'Ресурсы'),
              value: inventory.resources.length,
            ),
            _MetricCard(label: strings.ports, value: inventory.leases.length),
          ],
        ),
        if (inventory.partial || inventory.blockers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppStatus(
                  label: strings.text(
                    en: 'Inventory is partial and remains read-only',
                    ru: 'Инвентарь неполный и доступен только для чтения',
                  ),
                  tone: AppStatusTone.warning,
                ),
                for (final blocker in inventory.blockers) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(blocker.message),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

final class NativeProjectsScreen extends StatelessWidget {
  const NativeProjectsScreen({
    required this.controller,
    required this.inventory,
    super.key,
  });

  final AppController controller;
  final NativeGatewayInventory inventory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (inventory.projects.isEmpty) {
      return Center(
        child: AppStatus(
          label: strings.text(
            en: 'No projects are granted to this account.',
            ru: 'Этому аккаунту пока не предоставлены проекты.',
          ),
          tone: AppStatusTone.info,
        ),
      );
    }
    return ListView.separated(
      key: const ValueKey<String>('native-projects'),
      itemCount: inventory.projects.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final project = inventory.projects[index];
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                project.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              AppStatus(
                label: _resourceStateLabel(strings, project.state),
                tone: statusTone(project.state.name),
              ),
              const SizedBox(height: 12),
              _NativeActionButtons(
                allowed: (action) =>
                    controller.canActOnNativeProject(project, action),
                run: (action) => _confirmAndRun(
                  context,
                  project.displayName,
                  action,
                  () => controller.runNativeProjectAction(project, action),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class NativeResourcesScreen extends StatelessWidget {
  const NativeResourcesScreen({
    required this.controller,
    required this.inventory,
    required this.kind,
    super.key,
  });

  final AppController controller;
  final NativeGatewayInventory inventory;
  final NativeGatewayResourceKind kind;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final kindLabel = _resourceKindLabel(strings, kind);
    final resources = inventory.resources
        .where((resource) => resource.kind == kind)
        .toList(growable: false);
    if (resources.isEmpty) {
      return Center(
        child: AppStatus(
          label: strings.text(
            en: 'No authorized $kindLabel resources.',
            ru: 'Нет доступных ресурсов типа «$kindLabel».',
          ),
          tone: AppStatusTone.info,
        ),
      );
    }
    return ListView.separated(
      key: ValueKey<String>('native-resources-${kind.name}'),
      itemCount: resources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final resource = resources[index];
        final logGate = controller.canReadNativeLogs(resource);
        final projectLabel = _projectLabel(strings, inventory, resource);
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                resource.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                projectLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appTokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  AppStatus(
                    label: _resourceStateLabel(strings, resource.state),
                    tone: statusTone(resource.state.name),
                  ),
                  if (resource.port != null)
                    AppStatus(
                      label: strings.text(
                        en: 'Port ${resource.port}',
                        ru: 'Порт ${resource.port}',
                      ),
                      tone: AppStatusTone.info,
                    ),
                  if (resource.cpuPercent != null)
                    AppStatus(
                      label: 'CPU ${resource.cpuPercent!.toStringAsFixed(1)}%',
                    ),
                ],
              ),
              for (final blocker in resource.blockers) ...<Widget>[
                const SizedBox(height: 8),
                AppStatus(label: blocker.message, tone: AppStatusTone.warning),
              ],
              const SizedBox(height: 12),
              _NativeActionButtons(
                allowed: (action) =>
                    controller.canActOnNativeResource(resource, action),
                run: (action) => _confirmAndRun(
                  context,
                  resource.displayName,
                  action,
                  () => controller.runNativeResourceAction(resource, action),
                ),
              ),
              const SizedBox(height: 8),
              AppButton(
                label: strings.text(en: 'View logs', ru: 'Показать логи'),
                variant: AppButtonVariant.text,
                onPressed: logGate.allowed
                    ? () => _showLogs(context, controller, resource)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

final class NativePortsScreen extends StatelessWidget {
  const NativePortsScreen({
    required this.controller,
    required this.inventory,
    super.key,
  });

  final AppController controller;
  final NativeGatewayInventory inventory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                strings.text(
                  en: '${inventory.leases.length} port leases',
                  ru: 'Аренд портов: ${inventory.leases.length}',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            AppButton(
              label: strings.text(en: 'Lease port', ru: 'Арендовать порт'),
              icon: const Icon(Icons.add_rounded),
              onPressed: _canCreateLease()
                  ? () => _showLeaseDialog(context)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: inventory.leases.isEmpty
              ? Center(
                  child: AppStatus(
                    label: strings.text(
                      en: 'No retained port leases.',
                      ru: 'Сохранённых аренд портов нет.',
                    ),
                    tone: AppStatusTone.info,
                  ),
                )
              : ListView.separated(
                  key: const ValueKey<String>('native-port-leases'),
                  itemCount: inventory.leases.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final lease = inventory.leases[index];
                    final gate = controller.canManageNativeLease(
                      projectId: lease.projectId,
                      leaseId: lease.id,
                    );
                    return AppCard(
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${lease.port} · ${lease.purpose}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                AppStatus(
                                  label: _leaseStatusLabel(
                                    strings,
                                    lease,
                                    DateTime.now(),
                                  ),
                                  tone: statusTone(
                                    _leaseStatusCode(lease, DateTime.now()),
                                  ),
                                ),
                                if (lease.expiresAt != null) ...<Widget>[
                                  const SizedBox(height: 8),
                                  Text(
                                    strings.text(
                                      en: 'Expires ${lease.expiresAt!.toLocal()}',
                                      ru: 'Истекает ${lease.expiresAt!.toLocal()}',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          AppButton(
                            label: strings.text(
                              en: 'Release',
                              ru: 'Освободить',
                            ),
                            variant: AppButtonVariant.danger,
                            onPressed: gate.allowed
                                ? () => _confirmRelease(context, lease)
                                : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  bool _canCreateLease() {
    for (final project in inventory.projects) {
      final hasServer = inventory.resources.any(
        (resource) =>
            resource.kind == NativeGatewayResourceKind.server &&
            resource.projectId == project.id,
      );
      if (hasServer &&
          controller.canManageNativeLease(projectId: project.id).allowed) {
        return true;
      }
    }
    return false;
  }

  Future<void> _showLeaseDialog(BuildContext context) async {
    final eligibleProjects = inventory.projects
        .where(
          (project) =>
              controller.canManageNativeLease(projectId: project.id).allowed &&
              inventory.resources.any(
                (resource) =>
                    resource.kind == NativeGatewayResourceKind.server &&
                    resource.projectId == project.id,
              ),
        )
        .toList(growable: false);
    if (eligibleProjects.isEmpty) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _NativeLeaseDialog(
        controller: controller,
        inventory: inventory,
        initialProject: eligibleProjects.first,
      ),
    );
  }

  Future<void> _confirmRelease(
    BuildContext context,
    NativeGatewayPortLease lease,
  ) async {
    final confirmed = await _confirmation(
      context,
      title: AppStrings.of(context).text(
        en: 'Release port ${lease.port}?',
        ru: 'Освободить порт ${lease.port}?',
      ),
      consequence: AppStrings.of(context).text(
        en: 'The exact lease for “${lease.purpose}” will stop reserving this port.',
        ru: 'Выбранная аренда «${lease.purpose}» перестанет резервировать этот порт.',
      ),
    );
    if (confirmed) {
      await controller.releaseNativePort(lease);
    }
  }
}

final class NativeEventsScreen extends StatefulWidget {
  const NativeEventsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<NativeEventsScreen> createState() => _NativeEventsScreenState();
}

final class _NativeEventsScreenState extends State<NativeEventsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.controller.state.nativeEvents.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.loadNativeEvents();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final state = widget.controller.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                strings.text(en: 'Event history', ru: 'История событий'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            AppButton(
              label: strings.refresh,
              variant: AppButtonVariant.secondary,
              onPressed: state.nativeEventsLoading
                  ? null
                  : () => widget.controller.loadNativeEvents(refresh: true),
            ),
          ],
        ),
        if (state.nativeEventsError != null) ...<Widget>[
          const SizedBox(height: 12),
          AppStatus(
            label: state.nativeEventsError!,
            tone: AppStatusTone.danger,
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: state.nativeEvents.isEmpty && !state.nativeEventsLoading
              ? Center(
                  child: AppStatus(
                    label: strings.text(
                      en: 'No events were returned.',
                      ru: 'События не получены.',
                    ),
                    tone: AppStatusTone.info,
                  ),
                )
              : ListView.separated(
                  key: const ValueKey<String>('native-events'),
                  itemCount:
                      state.nativeEvents.length +
                      (state.nativeEventsHasMore ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == state.nativeEvents.length) {
                      return AppButton(
                        label: state.nativeEventsLoading
                            ? strings.loading
                            : strings.text(
                                en: 'Load more',
                                ru: 'Загрузить ещё',
                              ),
                        loading: state.nativeEventsLoading,
                        onPressed: state.nativeEventsLoading
                            ? null
                            : widget.controller.loadNativeEvents,
                      );
                    }
                    final event = state.nativeEvents[index];
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            event.message,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: <Widget>[
                              AppStatus(
                                label: event.kind,
                                tone: AppStatusTone.info,
                              ),
                              Text(event.occurredAt.toLocal().toString()),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

final class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}

final class _NativeActionButtons extends StatelessWidget {
  const _NativeActionButtons({required this.allowed, required this.run});

  final NativeActionGate Function(NativeGatewayResourceAction action) allowed;
  final void Function(NativeGatewayResourceAction action) run;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final action in NativeGatewayResourceAction.values)
          AppButton(
            label: _actionLabel(strings, action),
            variant: action == NativeGatewayResourceAction.stop
                ? AppButtonVariant.danger
                : action == NativeGatewayResourceAction.start
                ? AppButtonVariant.primary
                : AppButtonVariant.secondary,
            onPressed: allowed(action).allowed ? () => run(action) : null,
          ),
      ],
    );
  }
}

final class _NativeLeaseDialog extends StatefulWidget {
  const _NativeLeaseDialog({
    required this.controller,
    required this.inventory,
    required this.initialProject,
  });

  final AppController controller;
  final NativeGatewayInventory inventory;
  final NativeGatewayProject initialProject;

  @override
  State<_NativeLeaseDialog> createState() => _NativeLeaseDialogState();
}

final class _NativeLeaseDialogState extends State<_NativeLeaseDialog> {
  late NativeGatewayProject _project;
  late NativeGatewayResource _server;
  final _first = TextEditingController(text: '30000');
  final _last = TextEditingController(text: '39999');
  final _preferred = TextEditingController();
  final _purpose = TextEditingController();
  bool _busy = false;
  String? _error;

  List<NativeGatewayResource> get _servers => widget.inventory.resources
      .where(
        (resource) =>
            resource.kind == NativeGatewayResourceKind.server &&
            resource.projectId == _project.id,
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    _server = _servers.first;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _preferred.dispose();
    _purpose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.text(en: 'Lease a port', ru: 'Аренда порта')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButtonFormField<NativeGatewayProject>(
              initialValue: _project,
              decoration: InputDecoration(labelText: strings.projects),
              items: widget.inventory.projects
                  .where(
                    (project) => widget.controller
                        .canManageNativeLease(projectId: project.id)
                        .allowed,
                  )
                  .map(
                    (project) => DropdownMenuItem<NativeGatewayProject>(
                      value: project,
                      child: Text(project.displayName),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _busy
                  ? null
                  : (project) {
                      if (project == null) return;
                      setState(() {
                        _project = project;
                        _server = _servers.first;
                      });
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<NativeGatewayResource>(
              initialValue: _server,
              decoration: InputDecoration(labelText: strings.servers),
              items: _servers
                  .map(
                    (server) => DropdownMenuItem<NativeGatewayResource>(
                      value: server,
                      child: Text(server.displayName),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _busy
                  ? null
                  : (server) {
                      if (server != null) {
                        setState(() => _server = server);
                      }
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purpose,
              decoration: InputDecoration(
                labelText: strings.text(en: 'Purpose', ru: 'Назначение'),
              ),
              maxLength: 120,
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _first,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: strings.text(
                        en: 'First port',
                        ru: 'Начальный порт',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _last,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: strings.text(
                        en: 'Last port',
                        ru: 'Конечный порт',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _preferred,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: strings.text(
                  en: 'Preferred port (optional)',
                  ru: 'Предпочтительный порт (необязательно)',
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              AppStatus(label: _error!, tone: AppStatusTone.danger),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(strings.text(en: 'Cancel', ru: 'Отмена')),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(strings.text(en: 'Lease', ru: 'Арендовать')),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final first = int.tryParse(_first.text.trim());
    final last = int.tryParse(_last.text.trim());
    final preferred = _preferred.text.trim().isEmpty
        ? null
        : int.tryParse(_preferred.text.trim());
    final purpose = _purpose.text.trim();
    if (first == null ||
        last == null ||
        first < 1 ||
        last > 65535 ||
        first > last ||
        purpose.isEmpty ||
        (_preferred.text.trim().isNotEmpty && preferred == null)) {
      final strings = AppStrings.of(context);
      setState(
        () => _error = strings.text(
          en: 'Enter a purpose and a valid port range.',
          ru: 'Укажите назначение и корректный диапазон портов.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final lease = await widget.controller.leaseNativePort(
      project: _project,
      server: _server,
      firstPort: first,
      lastPort: last,
      purpose: purpose,
      preferredPort: preferred,
    );
    if (!mounted) return;
    if (lease == null) {
      setState(() {
        _busy = false;
        _error =
            widget.controller.state.connectionError ??
            AppStrings.of(
              context,
            ).text(en: 'Port lease failed.', ru: 'Не удалось арендовать порт.');
      });
      return;
    }
    Navigator.of(context).pop();
  }
}

Future<void> _showLogs(
  BuildContext context,
  AppController controller,
  NativeGatewayResource resource,
) async {
  final page = await controller.readNativeLogs(resource);
  if (page == null || !context.mounted) {
    return;
  }
  final strings = AppStrings.of(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        strings.text(
          en: '${resource.displayName}: logs',
          ru: '${resource.displayName}: логи',
        ),
      ),
      content: SizedBox(
        width: 720,
        child: page.lines.isEmpty
            ? AppStatus(
                label: strings.text(
                  en: 'No log lines were returned.',
                  ru: 'Строки логов не получены.',
                ),
                tone: AppStatusTone.info,
              )
            : SingleChildScrollView(
                child: SelectableText(
                  page.lines.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
      ],
    ),
  );
}

Future<void> _confirmAndRun(
  BuildContext context,
  String target,
  NativeGatewayResourceAction action,
  Future<NativeGatewayOperation?> Function() run,
) async {
  if (action != NativeGatewayResourceAction.start) {
    final strings = AppStrings.of(context);
    final confirmed = await _confirmation(
      context,
      title: strings.text(
        en: '${_actionLabel(strings, action)} $target?',
        ru: '${_actionLabel(strings, action)}: $target?',
      ),
      consequence: action == NativeGatewayResourceAction.stop
          ? strings.text(
              en: 'The selected resource will stop serving until it is started again.',
              ru: 'Выбранный ресурс остановится до следующего запуска.',
            )
          : strings.text(
              en: 'The selected resource will be stopped and started again.',
              ru: 'Выбранный ресурс будет остановлен и запущен заново.',
            ),
    );
    if (!confirmed) {
      return;
    }
  }
  await run();
}

Future<bool> _confirmation(
  BuildContext context, {
  required String title,
  required String consequence,
}) async {
  final strings = AppStrings.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(consequence),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.text(en: 'Cancel', ru: 'Отмена')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.text(en: 'Confirm', ru: 'Подтвердить')),
            ),
          ],
        ),
      ) ??
      false;
}

String _resourceKindLabel(AppStrings strings, NativeGatewayResourceKind kind) =>
    switch (kind) {
      NativeGatewayResourceKind.server => strings.text(
        en: 'server',
        ru: 'сервер',
      ),
      NativeGatewayResourceKind.container => strings.text(
        en: 'container',
        ru: 'контейнер',
      ),
      NativeGatewayResourceKind.database => strings.text(
        en: 'database',
        ru: 'база данных',
      ),
      NativeGatewayResourceKind.worktree => strings.text(
        en: 'worktree',
        ru: 'рабочее дерево',
      ),
    };

String _projectLabel(
  AppStrings strings,
  NativeGatewayInventory inventory,
  NativeGatewayResource resource,
) {
  final projectId = resource.projectId;
  if (projectId == null) {
    return strings.text(en: 'Unassigned resource', ru: 'Ресурс без проекта');
  }
  final matches = inventory.projects
      .where((project) => project.id == projectId)
      .toList(growable: false);
  if (matches.length != 1) {
    return strings.text(en: 'Project is unavailable', ru: 'Проект недоступен');
  }
  return strings.text(
    en: 'Project: ${matches.single.displayName}',
    ru: 'Проект: ${matches.single.displayName}',
  );
}

String _resourceStateLabel(
  AppStrings strings,
  NativeGatewayResourceState state,
) => switch (state) {
  NativeGatewayResourceState.running => strings.text(
    en: 'Running',
    ru: 'Запущен',
  ),
  NativeGatewayResourceState.stopped => strings.text(
    en: 'Stopped',
    ru: 'Остановлен',
  ),
  NativeGatewayResourceState.starting => strings.text(
    en: 'Starting',
    ru: 'Запускается',
  ),
  NativeGatewayResourceState.stopping => strings.text(
    en: 'Stopping',
    ru: 'Останавливается',
  ),
  NativeGatewayResourceState.unhealthy => strings.text(
    en: 'Unhealthy',
    ru: 'Неисправен',
  ),
  NativeGatewayResourceState.archived => strings.text(
    en: 'Archived',
    ru: 'В архиве',
  ),
  NativeGatewayResourceState.unknown => strings.text(
    en: 'Unknown',
    ru: 'Неизвестно',
  ),
};

String _actionLabel(AppStrings strings, NativeGatewayResourceAction action) =>
    switch (action) {
      NativeGatewayResourceAction.start => strings.text(
        en: 'Start',
        ru: 'Запустить',
      ),
      NativeGatewayResourceAction.stop => strings.text(
        en: 'Stop',
        ru: 'Остановить',
      ),
      NativeGatewayResourceAction.restart => strings.text(
        en: 'Restart',
        ru: 'Перезапустить',
      ),
    };

String _leaseStatusCode(NativeGatewayPortLease lease, DateTime now) {
  final expiry = lease.expiresAt;
  if (lease.status == NativeGatewayPortLeaseStatus.active &&
      expiry != null &&
      !expiry.isAfter(now.toUtc())) {
    return 'expired';
  }
  return lease.status.name;
}

String _leaseStatusLabel(
  AppStrings strings,
  NativeGatewayPortLease lease,
  DateTime now,
) => switch (_leaseStatusCode(lease, now)) {
  'active' => strings.text(en: 'Active', ru: 'Активна'),
  'released' => strings.text(en: 'Released', ru: 'Освобождена'),
  'stale' => strings.text(en: 'Stale', ru: 'Устарела'),
  'expired' => strings.text(en: 'Expired', ru: 'Истекла'),
  _ => strings.text(en: 'Unknown', ru: 'Неизвестно'),
};
