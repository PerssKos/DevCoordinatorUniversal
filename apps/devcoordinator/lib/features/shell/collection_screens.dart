import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../core/coordinator/legacy_action_policy.dart';
import '../../core/localization/app_strings.dart';
import 'app_shell.dart';

final class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({
    required this.controller,
    required this.inventory,
    super.key,
  });

  final AppController controller;
  final CoordinatorInventory inventory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (inventory.projects.isEmpty) {
      return _EmptyCollection(
        icon: Icons.folder_off_outlined,
        message: strings.text(
          en: 'No canonical projects are in the committed inventory.',
          ru: 'В зафиксированном инвентаре нет канонических проектов.',
        ),
      );
    }
    final tokens = context.appTokens;
    final projectLabels = _projectPresentationLabels(
      inventory.projects,
      strings,
    );
    return ListView.separated(
      key: const ValueKey<String>('projects-screen'),
      itemCount: inventory.projects.length,
      separatorBuilder: (_, _) => SizedBox(height: tokens.spaceMd),
      itemBuilder: (context, index) {
        final project = inventory.projects[index];
        final servers = inventory.servers
            .where(
              (server) =>
                  server.repoId == project.id ||
                  server.projectRoot == project.canonicalRoot,
            )
            .length;
        final containers = inventory.containers
            .where(
              (container) =>
                  container.repoId == project.id ||
                  container.projectRoot == project.canonicalRoot,
            )
            .length;
        return _ProjectCard(
          controller: controller,
          project: project,
          presentationLabel: projectLabels[project]!,
          serverCount: servers,
          containerCount: containers,
        );
      },
    );
  }
}

final class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.controller,
    required this.project,
    required this.presentationLabel,
    required this.serverCount,
    required this.containerCount,
  });

  final AppController controller;
  final CoordinatorProject project;
  final String presentationLabel;
  final int serverCount;
  final int containerCount;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    final actionKey = controller.state.actionKey;
    final canMutate = controller.state.canMutate;
    final lifecycleSupported = controller.supports(
      CoordinatorCapability.projectLifecycle,
    );
    final actionable =
        project.id.isNotEmpty &&
        project.canonicalRoot.isNotEmpty &&
        project.displayName.trim().isNotEmpty;
    final canStartOrRestart =
        actionable && !project.startupFenced && lifecycleSupported && canMutate;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                ),
                child: Padding(
                  padding: EdgeInsets.all(tokens.spaceSm),
                  child: Icon(Icons.folder_rounded, color: tokens.accent),
                ),
              ),
              SizedBox(width: tokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      presentationLabel,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              AppStatus(
                label: project.startupFenced
                    ? strings.text(en: 'Fenced', ru: 'Запуск запрещён')
                    : project.installationStatus,
                tone: project.startupFenced
                    ? AppStatusTone.warning
                    : statusTone(project.installationStatus),
              ),
            ],
          ),
          SizedBox(height: tokens.spaceMd),
          Wrap(
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: <Widget>[
              AppStatus(
                label: '$serverCount ${strings.servers.toLowerCase()}',
                tone: AppStatusTone.info,
              ),
              AppStatus(
                label: '$containerCount ${strings.containers.toLowerCase()}',
                tone: AppStatusTone.neutral,
              ),
            ],
          ),
          SizedBox(height: tokens.spaceMd),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: <Widget>[
              AppButton(
                label: strings.start,
                variant: AppButtonVariant.secondary,
                loading: actionKey == 'project:${project.id}:start',
                onPressed: canStartOrRestart
                    ? () => controller.runProjectAction(
                        project,
                        CoordinatorProjectAction.start,
                        presentationLabel: presentationLabel,
                      )
                    : null,
              ),
              AppButton(
                label: strings.restart,
                variant: AppButtonVariant.secondary,
                loading: actionKey == 'project:${project.id}:restart',
                onPressed: canStartOrRestart
                    ? () => _confirmAction(
                        context,
                        title: strings.restart,
                        target: presentationLabel,
                        onConfirmed: () => controller.runProjectAction(
                          project,
                          CoordinatorProjectAction.restart,
                          presentationLabel: presentationLabel,
                        ),
                      )
                    : null,
              ),
              AppButton(
                label: strings.stop,
                variant: AppButtonVariant.danger,
                loading: actionKey == 'project:${project.id}:stop',
                onPressed: actionable && lifecycleSupported && canMutate
                    ? () => _confirmAction(
                        context,
                        title: strings.stop,
                        target: presentationLabel,
                        onConfirmed: () => controller.runProjectAction(
                          project,
                          CoordinatorProjectAction.stop,
                          presentationLabel: presentationLabel,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          if (project.startupFenced) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Start and restart are blocked by the committed startup fence. Stop remains available.',
                ru: 'Запуск и перезапуск заблокированы зафиксированным ограничением. Остановка остаётся доступной.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ],
          if (!lifecycleSupported) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Project controls are unavailable because this connection contract does not support project lifecycle operations.',
                ru: 'Управление проектом недоступно: контракт подключения не поддерживает операции жизненного цикла проектов.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ],
        ],
      ),
    );
  }
}

final class ServersScreen extends StatelessWidget {
  const ServersScreen({
    required this.controller,
    required this.inventory,
    super.key,
  });

  final AppController controller;
  final CoordinatorInventory inventory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (inventory.servers.isEmpty) {
      return _EmptyCollection(
        icon: Icons.dns_outlined,
        message: strings.text(
          en: 'No servers are in the committed inventory.',
          ru: 'В зафиксированном инвентаре нет серверов.',
        ),
      );
    }
    final tokens = context.appTokens;
    final projectLabels = _projectPresentationLabels(
      inventory.projects,
      strings,
    );
    final serverLabels = _presentationLabels<CoordinatorServer>(
      inventory.servers,
      baseLabel: (server) => _serverBaseLabel(server, strings),
      stableKey: (server) =>
          '${server.id}\u0000${server.repoId ?? ''}\u0000'
          '${server.projectRoot ?? ''}',
    );
    return ListView.separated(
      key: const ValueKey<String>('servers-screen'),
      itemCount: inventory.servers.length,
      separatorBuilder: (_, _) => SizedBox(height: tokens.spaceMd),
      itemBuilder: (context, index) {
        final server = inventory.servers[index];
        return _ServerCard(
          controller: controller,
          server: server,
          presentationLabel: serverLabels[server]!,
          projectLabel: _projectPresentationName(
            inventory.projects,
            labels: projectLabels,
            repoId: server.repoId,
            projectRoot: server.projectRoot,
            strings: strings,
          ),
        );
      },
    );
  }
}

final class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.controller,
    required this.server,
    required this.presentationLabel,
    required this.projectLabel,
  });

  final AppController controller;
  final CoordinatorServer server;
  final String presentationLabel;
  final String projectLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    final actionKey = controller.state.actionKey;
    final canMutate = controller.state.canMutate;
    final canReadRemoteData = controller.state.canReadRemoteData;
    final lifecycleSupported = controller.supports(
      CoordinatorCapability.serverLifecycle,
    );
    final logsSupported = controller.supports(CoordinatorCapability.logsRead);
    final controlPolicy = legacyServerControlPolicy(server);
    final targetReady =
        server.repoId != null &&
        server.repoId!.isNotEmpty &&
        server.projectRoot != null &&
        server.projectRoot!.isNotEmpty &&
        server.name.trim().isNotEmpty;
    final canStart =
        targetReady && server.arguments.isNotEmpty && server.port != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.dns_rounded, color: tokens.accent),
              SizedBox(width: tokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      presentationLabel,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      projectLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppStatus(
                label: server.healthClassification ?? server.status,
                tone: statusTone(server.healthClassification ?? server.status),
              ),
            ],
          ),
          SizedBox(height: tokens.spaceMd),
          Wrap(
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: <Widget>[
              if (server.port != null)
                AppStatus(
                  label: '${strings.ports}: ${server.port}',
                  tone: AppStatusTone.info,
                ),
              if (server.usage?.cpuPercent != null)
                AppStatus(
                  label: 'CPU ${server.usage!.cpuPercent!.toStringAsFixed(1)}%',
                ),
              if (server.usage?.memoryBytes != null)
                AppStatus(label: _bytes(server.usage!.memoryBytes!)),
            ],
          ),
          SizedBox(height: tokens.spaceMd),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: <Widget>[
              AppButton(
                label: strings.logs,
                variant: AppButtonVariant.text,
                loading: actionKey == 'server:${server.id}:logs',
                onPressed: targetReady && logsSupported && canReadRemoteData
                    ? () => _showServerLogs(context)
                    : null,
              ),
              if (controlPolicy == LegacyServerControlPolicy.startOnly)
                AppButton(
                  label: strings.start,
                  variant: AppButtonVariant.secondary,
                  loading: actionKey == 'server:${server.id}:start',
                  onPressed: canStart && lifecycleSupported && canMutate
                      ? () => controller.runServerAction(
                          server,
                          CoordinatorResourceAction.start,
                          presentationLabel: _targetPresentationLabel(
                            presentationLabel,
                            projectLabel,
                          ),
                        )
                      : null,
                )
              else if (controlPolicy ==
                  LegacyServerControlPolicy.restartAndStop) ...<Widget>[
                AppButton(
                  label: strings.restart,
                  variant: AppButtonVariant.secondary,
                  loading: actionKey == 'server:${server.id}:restart',
                  onPressed: targetReady && lifecycleSupported && canMutate
                      ? () => _confirmAction(
                          context,
                          title: strings.restart,
                          target: _targetPresentationLabel(
                            presentationLabel,
                            projectLabel,
                          ),
                          onConfirmed: () => controller.runServerAction(
                            server,
                            CoordinatorResourceAction.restart,
                            presentationLabel: _targetPresentationLabel(
                              presentationLabel,
                              projectLabel,
                            ),
                          ),
                        )
                      : null,
                ),
                AppButton(
                  label: strings.stop,
                  variant: AppButtonVariant.danger,
                  loading: actionKey == 'server:${server.id}:stop',
                  onPressed: targetReady && lifecycleSupported && canMutate
                      ? () => _confirmAction(
                          context,
                          title: strings.stop,
                          target: _targetPresentationLabel(
                            presentationLabel,
                            projectLabel,
                          ),
                          onConfirmed: () => controller.runServerAction(
                            server,
                            CoordinatorResourceAction.stop,
                            presentationLabel: _targetPresentationLabel(
                              presentationLabel,
                              projectLabel,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ],
          ),
          if (!lifecycleSupported) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Server controls are unavailable because this connection contract does not support server lifecycle operations.',
                ru: 'Управление сервером недоступно: контракт подключения не поддерживает операции жизненного цикла серверов.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ] else if (!targetReady) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Actions are blocked because exact repository ownership is unavailable.',
                ru: 'Действия заблокированы: точная принадлежность репозиторию не доказана.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ] else if (controlPolicy ==
              LegacyServerControlPolicy.blocked) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Controls are blocked until the server lifecycle state and listener identity are conclusive.',
                ru: 'Управление заблокировано, пока состояние сервера и принадлежность слушателя не подтверждены однозначно.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ] else if (controlPolicy == LegacyServerControlPolicy.startOnly &&
              !canStart) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Start is blocked until committed launch arguments and an explicit port are available.',
                ru: 'Запуск заблокирован, пока не зафиксированы команда запуска и точный порт.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ],
          if (!logsSupported) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Logs are unavailable because this connection contract does not support log access.',
                ru: 'Журналы недоступны: контракт подключения не поддерживает доступ к журналам.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showServerLogs(BuildContext context) async {
    final result = await controller.readServerLogs(server);
    if (context.mounted && result != null) {
      await _showLogs(
        context,
        _targetPresentationLabel(presentationLabel, projectLabel),
        result,
      );
    }
  }
}

final class ContainersScreen extends StatelessWidget {
  const ContainersScreen({
    required this.controller,
    required this.inventory,
    super.key,
  });

  final AppController controller;
  final CoordinatorInventory inventory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (inventory.containers.isEmpty) {
      return _EmptyCollection(
        icon: Icons.view_in_ar_outlined,
        message: strings.text(
          en: 'No current containers are in the committed inventory.',
          ru: 'В зафиксированном инвентаре нет текущих контейнеров.',
        ),
      );
    }
    final tokens = context.appTokens;
    final projectLabels = _projectPresentationLabels(
      inventory.projects,
      strings,
    );
    final containerLabels = _presentationLabels<CoordinatorContainer>(
      inventory.containers,
      baseLabel: (container) => _containerBaseLabel(container, strings),
      stableKey: (container) =>
          '${container.containerId}\u0000${container.id}\u0000'
          '${container.repoId ?? ''}\u0000${container.projectRoot ?? ''}',
    );
    return ListView.separated(
      key: const ValueKey<String>('containers-screen'),
      itemCount: inventory.containers.length,
      separatorBuilder: (_, _) => SizedBox(height: tokens.spaceMd),
      itemBuilder: (context, index) {
        final container = inventory.containers[index];
        return _ContainerCard(
          controller: controller,
          container: container,
          presentationLabel: containerLabels[container]!,
          projectLabel: _projectPresentationName(
            inventory.projects,
            labels: projectLabels,
            repoId: container.repoId,
            projectRoot: container.projectRoot,
            strings: strings,
          ),
        );
      },
    );
  }
}

final class _ContainerCard extends StatelessWidget {
  const _ContainerCard({
    required this.controller,
    required this.container,
    required this.presentationLabel,
    required this.projectLabel,
  });

  final AppController controller;
  final CoordinatorContainer container;
  final String presentationLabel;
  final String projectLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    final actionKey = controller.state.actionKey;
    final canMutate = controller.state.canMutate;
    final canReadRemoteData = controller.state.canReadRemoteData;
    final lifecycleSupported = controller.supports(
      CoordinatorCapability.containerLifecycle,
    );
    final logsSupported = controller.supports(CoordinatorCapability.logsRead);
    final hasExactContainerId = RegExp(
      r'^[a-f0-9]{64}$',
    ).hasMatch(container.containerId);
    final targetReady =
        hasExactContainerId &&
        container.repoId != null &&
        container.repoId!.isNotEmpty &&
        container.projectRoot != null &&
        container.projectRoot!.isNotEmpty &&
        container.name.trim().isNotEmpty;
    final stopped =
        container.status.toLowerCase().contains('stop') ||
        container.status.toLowerCase().contains('exit');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.view_in_ar_rounded, color: tokens.accent),
              SizedBox(width: tokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      presentationLabel,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      projectLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    Text(
                      container.image ??
                          strings.text(
                            en: 'Image unavailable',
                            ru: 'Образ не указан',
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppStatus(
                label: container.status,
                tone: statusTone(container.status),
              ),
            ],
          ),
          SizedBox(height: tokens.spaceMd),
          Wrap(
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: <Widget>[
              for (final port in container.ports.where(
                (binding) => binding.hostPort != null,
              ))
                AppStatus(
                  label:
                      '${port.hostPort} → ${port.containerPort}/${port.protocol}',
                  tone: AppStatusTone.info,
                ),
              if (container.usage?.cpuPercent != null)
                AppStatus(
                  label:
                      'CPU ${container.usage!.cpuPercent!.toStringAsFixed(1)}%',
                ),
              if (container.usage?.memoryBytes != null)
                AppStatus(label: _bytes(container.usage!.memoryBytes!)),
            ],
          ),
          SizedBox(height: tokens.spaceMd),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: tokens.spaceSm,
            runSpacing: tokens.spaceSm,
            children: <Widget>[
              AppButton(
                label: strings.logs,
                variant: AppButtonVariant.text,
                loading: actionKey == 'container:${container.id}:logs',
                onPressed: targetReady && logsSupported && canReadRemoteData
                    ? () => _showContainerLogs(context)
                    : null,
              ),
              if (stopped)
                AppButton(
                  label: strings.start,
                  variant: AppButtonVariant.secondary,
                  loading: actionKey == 'container:${container.id}:start',
                  onPressed: targetReady && lifecycleSupported && canMutate
                      ? () => controller.runContainerAction(
                          container,
                          CoordinatorResourceAction.start,
                          presentationLabel: _targetPresentationLabel(
                            presentationLabel,
                            projectLabel,
                          ),
                        )
                      : null,
                )
              else ...<Widget>[
                AppButton(
                  label: strings.restart,
                  variant: AppButtonVariant.secondary,
                  loading: actionKey == 'container:${container.id}:restart',
                  onPressed: targetReady && lifecycleSupported && canMutate
                      ? () => _confirmAction(
                          context,
                          title: strings.restart,
                          target: _targetPresentationLabel(
                            presentationLabel,
                            projectLabel,
                          ),
                          onConfirmed: () => controller.runContainerAction(
                            container,
                            CoordinatorResourceAction.restart,
                            presentationLabel: _targetPresentationLabel(
                              presentationLabel,
                              projectLabel,
                            ),
                          ),
                        )
                      : null,
                ),
                AppButton(
                  label: strings.stop,
                  variant: AppButtonVariant.danger,
                  loading: actionKey == 'container:${container.id}:stop',
                  onPressed: targetReady && lifecycleSupported && canMutate
                      ? () => _confirmAction(
                          context,
                          title: strings.stop,
                          target: _targetPresentationLabel(
                            presentationLabel,
                            projectLabel,
                          ),
                          onConfirmed: () => controller.runContainerAction(
                            container,
                            CoordinatorResourceAction.stop,
                            presentationLabel: _targetPresentationLabel(
                              presentationLabel,
                              projectLabel,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ],
          ),
          if (!lifecycleSupported) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Container controls are unavailable because this connection contract does not support container lifecycle operations.',
                ru: 'Управление контейнером недоступно: контракт подключения не поддерживает операции жизненного цикла контейнеров.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ] else if (!targetReady) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Actions are blocked until a full immutable Docker container identifier and exact project ownership are available.',
                ru: 'Действия заблокированы, пока не доступны полный неизменяемый идентификатор Docker-контейнера и точная принадлежность проекту.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ],
          if (!logsSupported) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Logs are unavailable because this connection contract does not support log access.',
                ru: 'Журналы недоступны: контракт подключения не поддерживает доступ к журналам.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ] else if (!hasExactContainerId) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Logs are blocked because a full immutable Docker container identifier is unavailable.',
                ru: 'Журналы заблокированы: полный неизменяемый идентификатор Docker-контейнера недоступен.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ] else if (!targetReady) ...<Widget>[
            SizedBox(height: tokens.spaceSm),
            Text(
              strings.text(
                en: 'Logs are blocked because exact project ownership is unavailable.',
                ru: 'Журналы заблокированы: точная принадлежность проекту недоступна.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.warning),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showContainerLogs(BuildContext context) async {
    final result = await controller.readContainerLogs(container);
    if (context.mounted && result != null) {
      await _showLogs(
        context,
        _targetPresentationLabel(presentationLabel, projectLabel),
        result,
      );
    }
  }
}

final class PortsScreen extends StatelessWidget {
  const PortsScreen({
    required this.controller,
    required this.inventory,
    super.key,
  });

  final AppController controller;
  final CoordinatorInventory inventory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    final actionKey = controller.state.actionKey;
    final canMutate = controller.state.canMutate;
    final now = DateTime.now().toUtc();
    final portLeasesSupported = controller.supports(
      CoordinatorCapability.portLeases,
    );
    final hasEligibleLeaseServer = inventory.projects.any(
      (project) => _eligibleLeaseServers(inventory.servers, project).isNotEmpty,
    );
    final projectLabels = _projectPresentationLabels(
      inventory.projects,
      strings,
    );
    final leaseLabels = _presentationLabels<CoordinatorLease>(
      inventory.leases,
      baseLabel: (lease) => _leaseBaseLabel(lease, strings),
      stableKey: (lease) =>
          '${lease.id}\u0000${lease.repoId ?? ''}\u0000'
          '${lease.projectRoot ?? ''}\u0000${lease.port}',
    );
    return Column(
      key: const ValueKey<String>('ports-screen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                strings.text(
                  en: '${inventory.leases.length} visible leases',
                  ru: 'Видимых аренд: ${inventory.leases.length}',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            AppButton(
              label: strings.text(en: 'Lease a port', ru: 'Арендовать порт'),
              onPressed:
                  inventory.projects.isEmpty ||
                      !hasEligibleLeaseServer ||
                      !portLeasesSupported ||
                      !canMutate
                  ? null
                  : () => _showLeaseDialog(context),
            ),
          ],
        ),
        if (inventory.projects.isEmpty) ...<Widget>[
          SizedBox(height: tokens.spaceSm),
          AppStatus(
            label: strings.text(
              en: 'A canonical project is required before a port can be leased.',
              ru: 'Для аренды порта сначала нужен канонический проект.',
            ),
            tone: AppStatusTone.warning,
          ),
        ],
        if (inventory.projects.isNotEmpty &&
            !hasEligibleLeaseServer) ...<Widget>[
          SizedBox(height: tokens.spaceSm),
          AppStatus(
            label: strings.text(
              en: 'Port leasing requires an enrolled server with exact project ownership. None is available in this inventory.',
              ru: 'Для аренды порта нужен зарегистрированный сервер с точной принадлежностью проекту. В этом инвентаре такого сервера нет.',
            ),
            tone: AppStatusTone.warning,
          ),
        ],
        if (!portLeasesSupported) ...<Widget>[
          SizedBox(height: tokens.spaceSm),
          AppStatus(
            label: strings.text(
              en: 'Port changes are unavailable because this connection contract does not support port leases.',
              ru: 'Изменение портов недоступно: контракт подключения не поддерживает аренду портов.',
            ),
            tone: AppStatusTone.warning,
          ),
        ],
        if (controller.state.lastLease case final lease?) ...<Widget>[
          SizedBox(height: tokens.spaceMd),
          AppCard(
            raised: true,
            child: Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded, color: tokens.success),
                SizedBox(width: tokens.spaceMd),
                Expanded(
                  child: Text(
                    strings.text(
                      en: controller.state.hasStaleInventory
                          ? 'Port ${lease.port} was leased successfully. The retained list has not refreshed yet.'
                          : 'Port ${lease.port} was leased and is now visible in this collection.',
                      ru: controller.state.hasStaleInventory
                          ? 'Порт ${lease.port} успешно арендован. Сохранённый список ещё не обновлён.'
                          : 'Порт ${lease.port} арендован и теперь виден в этом списке.',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: strings.close,
                  onPressed: controller.dismissLastLease,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ],
        SizedBox(height: tokens.spaceMd),
        Expanded(
          child: inventory.leases.isEmpty
              ? _EmptyCollection(
                  icon: Icons.cable_outlined,
                  message: strings.text(
                    en: 'No active or retained port leases are visible.',
                    ru: 'Нет видимых активных или сохранённых аренд портов.',
                  ),
                )
              : ListView.separated(
                  itemCount: inventory.leases.length,
                  separatorBuilder: (_, _) => SizedBox(height: tokens.spaceMd),
                  itemBuilder: (context, index) {
                    final lease = inventory.leases[index];
                    final leaseLabel = leaseLabels[lease]!;
                    final projectLabel = _projectPresentationName(
                      inventory.projects,
                      labels: projectLabels,
                      repoId: lease.repoId,
                      projectRoot: lease.projectRoot,
                      strings: strings,
                    );
                    final exactTarget =
                        lease.repoId?.isNotEmpty == true &&
                        lease.projectRoot?.isNotEmpty == true;
                    final releasable = isLeaseReleasable(lease, now: now);
                    final expiresAt = lease.expiresAt?.toLocal();
                    final expiredByTime =
                        lease.expiresAt != null &&
                        !lease.expiresAt!.toUtc().isAfter(now);
                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: tokens.accent.withValues(alpha: 0.13),
                                  borderRadius: BorderRadius.circular(
                                    tokens.radiusMedium,
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(tokens.spaceSm),
                                  child: Text(
                                    '${lease.port}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: tokens.accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                              ),
                              SizedBox(width: tokens.spaceMd),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      leaseLabel,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      projectLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: tokens.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              AppStatus(
                                label: lease.status,
                                tone: statusTone(lease.status),
                              ),
                            ],
                          ),
                          if (expiresAt != null) ...<Widget>[
                            SizedBox(height: tokens.spaceSm),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: AppStatus(
                                label: strings.text(
                                  en: expiredByTime
                                      ? 'Expired $expiresAt'
                                      : 'Expires $expiresAt',
                                  ru: expiredByTime
                                      ? 'Истекла $expiresAt'
                                      : 'Истекает $expiresAt',
                                ),
                                tone: expiredByTime
                                    ? AppStatusTone.warning
                                    : AppStatusTone.info,
                              ),
                            ),
                          ],
                          SizedBox(height: tokens.spaceSm),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: tokens.spaceSm,
                            runSpacing: tokens.spaceSm,
                            children: <Widget>[
                              AppButton(
                                label: strings.text(
                                  en: 'Copy port',
                                  ru: 'Скопировать порт',
                                ),
                                variant: AppButtonVariant.text,
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: '${lease.port}'),
                                  );
                                },
                              ),
                              AppButton(
                                label: strings.text(
                                  en: 'Release',
                                  ru: 'Освободить',
                                ),
                                variant: AppButtonVariant.danger,
                                loading:
                                    actionKey == 'port:${lease.id}:release',
                                onPressed:
                                    exactTarget &&
                                        releasable &&
                                        portLeasesSupported &&
                                        canMutate
                                    ? () => _confirmAction(
                                        context,
                                        title: strings.text(
                                          en: 'Release',
                                          ru: 'Освободить',
                                        ),
                                        target:
                                            '${lease.port} — '
                                            '${_targetPresentationLabel(leaseLabel, projectLabel)}',
                                        onConfirmed: () => controller.releasePort(
                                          lease,
                                          presentationLabel:
                                              '${lease.port} — '
                                              '${_targetPresentationLabel(leaseLabel, projectLabel)}',
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                          if (!portLeasesSupported) ...<Widget>[
                            SizedBox(height: tokens.spaceSm),
                            Text(
                              strings.text(
                                en: 'Release is unavailable because this connection contract does not support port leases.',
                                ru: 'Освобождение недоступно: контракт подключения не поддерживает аренду портов.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: tokens.warning),
                            ),
                          ] else if (!exactTarget) ...<Widget>[
                            SizedBox(height: tokens.spaceSm),
                            Text(
                              strings.text(
                                en: 'Release is blocked because exact project ownership is unavailable.',
                                ru: 'Освобождение заблокировано: точная принадлежность проекту не доказана.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: tokens.warning),
                            ),
                          ] else if (!releasable) ...<Widget>[
                            SizedBox(height: tokens.spaceSm),
                            Text(
                              strings.text(
                                en: 'This retained lease is no longer active, or its expiry has passed. Release is unavailable.',
                                ru: 'Эта сохранённая аренда уже не активна либо срок её действия истёк. Освобождение недоступно.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: tokens.warning),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showLeaseDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PortLeaseDialog(
        controller: controller,
        projects: inventory.projects,
        servers: inventory.servers,
      ),
    );
  }
}

final class _PortLeaseDialog extends StatefulWidget {
  const _PortLeaseDialog({
    required this.controller,
    required this.projects,
    required this.servers,
  });

  final AppController controller;
  final List<CoordinatorProject> projects;
  final List<CoordinatorServer> servers;

  @override
  State<_PortLeaseDialog> createState() => _PortLeaseDialogState();
}

final class _PortLeaseDialogState extends State<_PortLeaseDialog> {
  final _formKey = GlobalKey<FormState>();
  late CoordinatorProject _project;
  CoordinatorServer? _server;
  late final TextEditingController _rangeController;
  late final TextEditingController _preferredController;
  late final TextEditingController _ttlController;
  late final TextEditingController _purposeController;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _project = widget.projects.firstWhere(
      (project) => _eligibleLeaseServers(widget.servers, project).isNotEmpty,
      orElse: () => widget.projects.first,
    );
    final eligibleServers = _eligibleLeaseServers(widget.servers, _project);
    _server = eligibleServers.isEmpty ? null : eligibleServers.first;
    _rangeController = TextEditingController(text: '3000-3999');
    _preferredController = TextEditingController();
    _ttlController = TextEditingController(text: '3600');
    _purposeController = TextEditingController();
  }

  @override
  void dispose() {
    _rangeController.dispose();
    _preferredController.dispose();
    _ttlController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    final projectLabels = _projectPresentationLabels(widget.projects, strings);
    final eligibleServers = _eligibleLeaseServers(widget.servers, _project);
    final serverLabels = _presentationLabels<CoordinatorServer>(
      eligibleServers,
      baseLabel: (server) => _serverBaseLabel(server, strings),
      stableKey: (server) => server.id,
    );
    final hasSelectedServer = _server != null;
    return AlertDialog(
      title: Text(strings.text(en: 'Lease a port', ru: 'Арендовать порт')),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DropdownButtonFormField<CoordinatorProject>(
                  initialValue: _project,
                  autofocus: true,
                  decoration: InputDecoration(labelText: strings.projects),
                  items: <DropdownMenuItem<CoordinatorProject>>[
                    for (final project in widget.projects)
                      DropdownMenuItem<CoordinatorProject>(
                        value: project,
                        child: Text(
                          projectLabels[project]!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (project) {
                          if (project == null) return;
                          final projectServers = _eligibleLeaseServers(
                            widget.servers,
                            project,
                          );
                          setState(() {
                            _project = project;
                            _server = projectServers.isEmpty
                                ? null
                                : projectServers.first;
                          });
                        },
                ),
                SizedBox(height: tokens.spaceMd),
                DropdownButtonFormField<CoordinatorServer>(
                  key: ValueKey<String>('lease-server-${_project.id}'),
                  initialValue: _server,
                  decoration: InputDecoration(
                    labelText: strings.text(
                      en: 'Enrolled server',
                      ru: 'Зарегистрированный сервер',
                    ),
                  ),
                  items: <DropdownMenuItem<CoordinatorServer>>[
                    for (final server in eligibleServers)
                      DropdownMenuItem<CoordinatorServer>(
                        value: server,
                        child: Text(
                          serverLabels[server]!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting || eligibleServers.isEmpty
                      ? null
                      : (server) {
                          setState(() {
                            _server = server;
                          });
                        },
                  validator: (server) => server == null
                      ? strings.text(
                          en: 'Select an enrolled server owned by this project.',
                          ru: 'Выберите зарегистрированный сервер этого проекта.',
                        )
                      : null,
                ),
                if (eligibleServers.isEmpty) ...<Widget>[
                  SizedBox(height: tokens.spaceSm),
                  AppStatus(
                    label: strings.text(
                      en: 'This project has no enrolled server with exact ownership, so a broker-backed lease cannot be requested.',
                      ru: 'У этого проекта нет зарегистрированного сервера с точной принадлежностью, поэтому запросить аренду через broker нельзя.',
                    ),
                    tone: AppStatusTone.warning,
                  ),
                ],
                SizedBox(height: tokens.spaceMd),
                TextFormField(
                  controller: _rangeController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: strings.text(
                      en: 'Allowed range',
                      ru: 'Разрешённый диапазон',
                    ),
                    hintText: '3000-3999',
                  ),
                  validator: (value) => _parseRange(value) == null
                      ? strings.text(
                          en: 'Use one port or a range within 1–65535.',
                          ru: 'Укажите порт или диапазон в пределах 1–65535.',
                        )
                      : null,
                ),
                SizedBox(height: tokens.spaceMd),
                TextFormField(
                  controller: _preferredController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: strings.text(
                      en: 'Preferred port (optional)',
                      ru: 'Предпочтительный порт (необязательно)',
                    ),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final preferred = int.tryParse(text);
                    final range = _parseRange(_rangeController.text);
                    if (preferred == null ||
                        range == null ||
                        preferred < range.$1 ||
                        preferred > range.$2) {
                      return strings.text(
                        en: 'Preferred port must be inside the range.',
                        ru: 'Предпочтительный порт должен входить в диапазон.',
                      );
                    }
                    return null;
                  },
                ),
                SizedBox(height: tokens.spaceMd),
                TextFormField(
                  controller: _ttlController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: strings.text(
                      en: 'Lease time, seconds (optional)',
                      ru: 'Срок аренды, секунд (необязательно)',
                    ),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final seconds = int.tryParse(text);
                    return seconds == null || seconds <= 0
                        ? strings.text(
                            en: 'Enter a positive number of seconds.',
                            ru: 'Введите положительное число секунд.',
                          )
                        : null;
                  },
                ),
                SizedBox(height: tokens.spaceMd),
                TextFormField(
                  controller: _purposeController,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted:
                      _submitting ||
                          !hasSelectedServer ||
                          !widget.controller.state.canMutate ||
                          !widget.controller.supports(
                            CoordinatorCapability.portLeases,
                          )
                      ? null
                      : (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: strings.text(
                      en: 'Purpose (optional)',
                      ru: 'Назначение (необязательно)',
                    ),
                  ),
                ),
                if (_error != null) ...<Widget>[
                  SizedBox(height: tokens.spaceMd),
                  AppStatus(label: _error!, tone: AppStatusTone.danger),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: strings.cancel,
          variant: AppButtonVariant.text,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: strings.text(en: 'Lease', ru: 'Арендовать'),
          loading: _submitting,
          onPressed:
              _submitting ||
                  !hasSelectedServer ||
                  !widget.controller.state.canMutate ||
                  !widget.controller.supports(CoordinatorCapability.portLeases)
              ? null
              : _submit,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!widget.controller.state.canMutate ||
        !widget.controller.supports(CoordinatorCapability.portLeases)) {
      setState(() {
        _error = AppStrings.of(context).text(
          en: 'The retained snapshot is read-only until refresh succeeds.',
          ru: 'Сохранённый снимок доступен только для чтения до успешного обновления.',
        );
      });
      return;
    }
    final server = _server;
    if (server == null) {
      setState(() {
        _error = AppStrings.of(context).text(
          en: 'Select an enrolled server owned by this project.',
          ru: 'Выберите зарегистрированный сервер этого проекта.',
        );
      });
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final range = _parseRange(_rangeController.text)!;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final preferredText = _preferredController.text.trim();
    final ttlText = _ttlController.text.trim();
    final lease = await widget.controller.leasePort(
      project: _project,
      server: server,
      firstPort: range.$1,
      lastPort: range.$2,
      preferredPort: preferredText.isEmpty ? null : int.parse(preferredText),
      ttl: ttlText.isEmpty ? null : Duration(seconds: int.parse(ttlText)),
      purpose: _purposeController.text,
    );
    if (!mounted) return;
    if (lease != null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error =
          widget.controller.state.connectionError ??
          AppStrings.of(context).text(
            en: 'The coordinator did not return a lease.',
            ru: 'Координатор не вернул аренду.',
          );
    });
  }

  static (int, int)? _parseRange(String? value) {
    final match = RegExp(
      r'^([0-9]{1,5})(?:-([0-9]{1,5}))?$',
    ).firstMatch(value?.trim() ?? '');
    if (match == null) return null;
    final first = int.parse(match.group(1)!);
    final last = int.parse(match.group(2) ?? match.group(1)!);
    if (first < 1 || last > 65535 || first > last) return null;
    return (first, last);
  }
}

final class EventsScreen extends StatelessWidget {
  const EventsScreen({required this.inventory, super.key});

  final CoordinatorInventory inventory;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    return Column(
      key: const ValueKey<String>('events-screen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppStatus(
          label: strings.text(
            en: 'Recent inventory snapshot — full cursor history is not loaded in this build.',
            ru: 'Недавний снимок инвентаря — полная история по курсору в этой сборке не загружается.',
          ),
          tone: AppStatusTone.info,
        ),
        SizedBox(height: tokens.spaceMd),
        Expanded(
          child: inventory.events.isEmpty
              ? _EmptyCollection(
                  icon: Icons.receipt_long_outlined,
                  message: strings.text(
                    en: 'No recent events are present in the inventory snapshot.',
                    ru: 'В снимке инвентаря нет недавних событий.',
                  ),
                )
              : ListView.separated(
                  itemCount: inventory.events.length,
                  separatorBuilder: (_, _) => SizedBox(height: tokens.spaceSm),
                  itemBuilder: (context, index) {
                    final event = inventory.events[index];
                    return AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.bolt_rounded, color: tokens.info),
                          SizedBox(width: tokens.spaceMd),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  event.message ?? event.code ?? event.kind,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                SizedBox(height: tokens.spaceXs),
                                Text(
                                  '${event.kind} · ${event.occurredAt.toLocal()}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: tokens.textSecondary),
                                ),
                              ],
                            ),
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

final class MoreScreen extends StatelessWidget {
  const MoreScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.appTokens;
    final items = <(IconData, String, AppSection)>[
      (Icons.cable_rounded, strings.ports, AppSection.ports),
      (Icons.receipt_long_rounded, strings.events, AppSection.events),
      (Icons.settings_rounded, strings.settings, AppSection.settings),
    ];
    return ListView.separated(
      key: const ValueKey<String>('more-screen'),
      itemCount: items.length,
      separatorBuilder: (_, _) => SizedBox(height: tokens.spaceMd),
      itemBuilder: (context, index) {
        final item = items[index];
        return AppCard(
          onTap: () => controller.selectSection(item.$3),
          child: Row(
            children: <Widget>[
              Icon(item.$1, color: tokens.accent),
              SizedBox(width: tokens.spaceMd),
              Expanded(
                child: Text(
                  item.$2,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        );
      },
    );
  }
}

final class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return ListView(
      children: <Widget>[
        AppCard(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spaceXl),
            child: Column(
              children: <Widget>[
                Icon(icon, size: 52, color: tokens.textSecondary),
                SizedBox(height: tokens.spaceMd),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmAction(
  BuildContext context, {
  required String title,
  required String target,
  required Future<void> Function() onConfirmed,
}) async {
  final strings = AppStrings.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        strings.text(
          en: '$title the exact target “$target”? The coordinator will revalidate ownership and current state.',
          ru: '$title точную цель «$target»? Координатор повторно проверит владельца и текущее состояние.',
        ),
      ),
      actions: <Widget>[
        AppButton(
          label: strings.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: title,
          variant: title == strings.stop
              ? AppButtonVariant.danger
              : AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (confirmed == true) await onConfirmed();
}

Future<void> _showLogs(
  BuildContext context,
  String target,
  CoordinatorLogResult result,
) {
  final strings = AppStrings.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) {
      final tokens = context.appTokens;
      return AlertDialog(
        title: Text('${strings.logs}: $target'),
        content: SizedBox(
          width: 760,
          height: 440,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
              border: Border.all(color: tokens.outline),
            ),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(tokens.spaceMd),
                child: SelectableText(
                  result.text.isEmpty
                      ? strings.text(en: 'Log is empty.', ru: 'Лог пуст.')
                      : result.text,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: <Widget>[
          if (result.truncated)
            AppStatus(
              label: strings.text(en: 'Truncated', ru: 'Обрезано'),
              tone: AppStatusTone.warning,
            ),
          AppButton(
            label: strings.close,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}

String _projectPresentationName(
  List<CoordinatorProject> projects, {
  required Map<CoordinatorProject, String> labels,
  required String? repoId,
  required String? projectRoot,
  required AppStrings strings,
}) {
  final normalizedRepoId = repoId?.trim();
  final normalizedRoot = projectRoot?.trim();
  final matches = projects
      .where(
        (project) =>
            (normalizedRepoId?.isNotEmpty == true &&
                project.id == normalizedRepoId) ||
            (normalizedRoot?.isNotEmpty == true &&
                project.canonicalRoot == normalizedRoot),
      )
      .toList(growable: false);
  if (matches.length == 1) {
    return labels[matches.single]!;
  }
  return strings.text(en: 'Project unavailable', ru: 'Проект не определён');
}

Map<CoordinatorProject, String> _projectPresentationLabels(
  List<CoordinatorProject> projects,
  AppStrings strings,
) {
  return _presentationLabels<CoordinatorProject>(
    projects,
    baseLabel: (project) => projectName(project, strings),
    stableKey: (project) => '${project.id}\u0000${project.canonicalRoot}',
  );
}

List<CoordinatorServer> _eligibleLeaseServers(
  List<CoordinatorServer> servers,
  CoordinatorProject project,
) {
  final ownedServers = servers
      .where(
        (server) =>
            server.id.trim().isNotEmpty &&
            server.name.trim().isNotEmpty &&
            server.repoId == project.id &&
            server.projectRoot == project.canonicalRoot,
      )
      .toList(growable: false);
  final nameCounts = <String, int>{};
  for (final server in ownedServers) {
    nameCounts.update(server.name, (count) => count + 1, ifAbsent: () => 1);
  }
  return ownedServers
      .where((server) => nameCounts[server.name] == 1)
      .toList(growable: false);
}

Map<T, String> _presentationLabels<T>(
  List<T> items, {
  required String Function(T item) baseLabel,
  required String Function(T item) stableKey,
}) {
  final entries = <_PresentationEntry<T>>[
    for (var index = 0; index < items.length; index += 1)
      _PresentationEntry<T>(
        item: items[index],
        originalIndex: index,
        baseLabel: baseLabel(items[index]).trim(),
        stableKey: stableKey(items[index]),
      ),
  ]..sort(_comparePresentationEntries);

  final byBaseLabel = <String, List<_PresentationEntry<T>>>{};
  for (final entry in entries) {
    byBaseLabel
        .putIfAbsent(entry.baseLabel, () => <_PresentationEntry<T>>[])
        .add(entry);
  }
  for (final group in byBaseLabel.values) {
    for (var index = 0; index < group.length; index += 1) {
      group[index].label = group.length == 1
          ? group[index].baseLabel
          : '${group[index].baseLabel} · ${index + 1}/${group.length}';
    }
  }

  // A natural label can itself look like an ordinal label. Repeatedly suffix
  // only exact collisions, keeping the result deterministic and user-safe.
  for (var pass = 0; pass <= entries.length; pass += 1) {
    final collisions = <String, List<_PresentationEntry<T>>>{};
    for (final entry in entries) {
      collisions
          .putIfAbsent(entry.label, () => <_PresentationEntry<T>>[])
          .add(entry);
    }
    final duplicateGroups = collisions.values
        .where((group) => group.length > 1)
        .toList(growable: false);
    if (duplicateGroups.isEmpty) break;
    for (final group in duplicateGroups) {
      group.sort(_comparePresentationEntries);
      final collidedLabel = group.first.label;
      for (var index = 0; index < group.length; index += 1) {
        group[index].label = '$collidedLabel · ${index + 1}/${group.length}';
      }
    }
  }

  final labels = Map<T, String>.identity();
  for (final entry in entries) {
    labels[entry.item] = entry.label;
  }
  return labels;
}

int _comparePresentationEntries<T>(
  _PresentationEntry<T> left,
  _PresentationEntry<T> right,
) {
  final stableOrder = left.stableKey.compareTo(right.stableKey);
  if (stableOrder != 0) return stableOrder;
  return left.originalIndex.compareTo(right.originalIndex);
}

String _serverBaseLabel(CoordinatorServer server, AppStrings strings) {
  final name = server.name.trim();
  return name.isEmpty
      ? strings.text(en: 'Unnamed server', ru: 'Сервер без названия')
      : name;
}

String _containerBaseLabel(CoordinatorContainer container, AppStrings strings) {
  final name = container.name.trim();
  return name.isEmpty
      ? strings.text(en: 'Unnamed container', ru: 'Контейнер без названия')
      : name;
}

String _leaseBaseLabel(CoordinatorLease lease, AppStrings strings) {
  final purpose = lease.purpose?.trim() ?? '';
  return purpose.isEmpty
      ? strings.text(en: 'Port lease', ru: 'Аренда порта')
      : purpose;
}

String _targetPresentationLabel(String resourceLabel, String projectLabel) {
  return '$resourceLabel — $projectLabel';
}

final class _PresentationEntry<T> {
  _PresentationEntry({
    required this.item,
    required this.originalIndex,
    required this.baseLabel,
    required this.stableKey,
  }) : label = baseLabel;

  final T item;
  final int originalIndex;
  final String baseLabel;
  final String stableKey;
  String label;
}

String _bytes(int value) {
  if (value >= 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (value >= 1024) {
    return '${(value / 1024).toStringAsFixed(1)} KB';
  }
  return '$value B';
}
