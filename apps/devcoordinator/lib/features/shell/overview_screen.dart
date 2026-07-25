import 'package:coordinator_client/coordinator_client.dart';
import 'package:devcoordinator_design/devcoordinator_design.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../core/localization/app_strings.dart';

final class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
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
    final unhealthyServers = inventory.servers
        .where((server) => _needsAttention(server.status, server.healthOk))
        .toList(growable: false);
    final unhealthyContainers = inventory.containers
        .where((container) => _needsAttention(container.status, null))
        .toList(growable: false);
    final expiredLeases = inventory.leases
        .where(
          (lease) =>
              lease.status.toLowerCase().contains('expired') ||
              (lease.expiresAt?.isBefore(DateTime.now().toUtc()) ?? false),
        )
        .toList(growable: false);
    final attentionCount =
        unhealthyServers.length +
        unhealthyContainers.length +
        expiredLeases.length +
        inventory.unassignedResources.length;

    return ListView(
      key: const ValueKey<String>('overview-screen'),
      children: <Widget>[
        Text(
          attentionCount == 0
              ? strings.text(
                  en: 'Everything observable is quiet',
                  ru: 'Всё наблюдаемое работает спокойно',
                )
              : strings.text(
                  en: '$attentionCount items need attention',
                  ru: 'Требуют внимания: $attentionCount',
                ),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        SizedBox(height: tokens.spaceSm),
        Text(
          inventory.updatedAt == null
              ? strings.text(
                  en: 'Committed coordinator snapshot',
                  ru: 'Зафиксированный снимок координатора',
                )
              : strings.text(
                  en: 'Updated ${_dateTime(inventory.updatedAt!)}',
                  ru: 'Обновлено ${_dateTime(inventory.updatedAt!)}',
                ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
        SizedBox(height: tokens.spaceLg),
        Wrap(
          spacing: tokens.spaceMd,
          runSpacing: tokens.spaceMd,
          children: <Widget>[
            _SummaryCard(
              icon: Icons.folder_rounded,
              label: strings.projects,
              value: inventory.projects.length,
              tone: AppStatusTone.info,
              onTap: () => controller.selectSection(_sectionProjects),
            ),
            _SummaryCard(
              icon: Icons.dns_rounded,
              label: strings.servers,
              value: inventory.servers.length,
              tone: unhealthyServers.isEmpty
                  ? AppStatusTone.success
                  : AppStatusTone.danger,
              onTap: () => controller.selectSection(_sectionServers),
            ),
            _SummaryCard(
              icon: Icons.view_in_ar_rounded,
              label: strings.containers,
              value: inventory.containers.length,
              tone: unhealthyContainers.isEmpty
                  ? AppStatusTone.success
                  : AppStatusTone.danger,
              onTap: () => controller.selectSection(_sectionContainers),
            ),
            _SummaryCard(
              icon: Icons.cable_rounded,
              label: strings.ports,
              value: inventory.leases.length,
              tone: expiredLeases.isEmpty
                  ? AppStatusTone.neutral
                  : AppStatusTone.warning,
              onTap: () => controller.selectSection(_sectionPorts),
            ),
          ],
        ),
        SizedBox(height: tokens.spaceLg),
        if (attentionCount > 0) ...<Widget>[
          Text(
            strings.text(en: 'Needs attention', ru: 'Требует внимания'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: tokens.spaceSm),
          AppCard(
            child: Column(
              children: <Widget>[
                for (final server in unhealthyServers)
                  _AttentionRow(
                    icon: Icons.dns_rounded,
                    title: server.name,
                    detail: server.healthClassification ?? server.status,
                    onTap: () => controller.selectSection(_sectionServers),
                  ),
                for (final container in unhealthyContainers)
                  _AttentionRow(
                    icon: Icons.view_in_ar_rounded,
                    title: container.name,
                    detail: container.status,
                    onTap: () => controller.selectSection(_sectionContainers),
                  ),
                for (final lease in expiredLeases)
                  _AttentionRow(
                    icon: Icons.cable_rounded,
                    title: '${strings.ports} ${lease.port}',
                    detail: lease.status,
                    onTap: () => controller.selectSection(_sectionPorts),
                  ),
                for (final resource in inventory.unassignedResources)
                  _AttentionRow(
                    icon: Icons.link_off_rounded,
                    title: resource.displayName,
                    detail: resource.explanation,
                  ),
              ],
            ),
          ),
          SizedBox(height: tokens.spaceLg),
        ],
        if (controller.state.lastActionResult != null) ...<Widget>[
          Text(
            strings.text(en: 'Last operation', ru: 'Последняя операция'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: tokens.spaceSm),
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppStatus(
                  label:
                      controller.state.lastActionResult!.status ??
                      (controller.state.lastActionResult!.ok == false
                          ? strings.text(en: 'Failed', ru: 'Ошибка')
                          : strings.text(en: 'Completed', ru: 'Завершено')),
                  tone: controller.state.lastActionResult!.ok == false
                      ? AppStatusTone.danger
                      : AppStatusTone.success,
                ),
                SizedBox(width: tokens.spaceMd),
                Expanded(
                  child: Text(
                    controller.state.lastActionLabel ?? '',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.spaceLg),
        ],
        Text(
          strings.text(en: 'Recent events', ru: 'Последние события'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SizedBox(height: tokens.spaceSm),
        if (inventory.events.isEmpty)
          AppCard(child: Text(strings.noData))
        else
          AppCard(
            child: Column(
              children: <Widget>[
                for (final event in inventory.events.take(6))
                  _EventRow(event: event),
              ],
            ),
          ),
        SizedBox(height: tokens.spaceXl),
      ],
    );
  }

  static bool _needsAttention(String status, bool? healthOk) {
    final normalized = status.toLowerCase();
    if (healthOk == false) return true;
    return normalized.contains('unhealthy') ||
        normalized.contains('wrong') ||
        normalized.contains('failed') ||
        normalized.contains('error') ||
        normalized.contains('unknown');
  }

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

// Keeping navigation constants local avoids feature imports from the shell's
// implementation while preserving exact enum values.
const _sectionProjects = AppSection.projects;
const _sectionServers = AppSection.servers;
const _sectionContainers = AppSection.containers;
const _sectionPorts = AppSection.ports;

final class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final AppStatusTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return SizedBox(
      width: 228,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: tokens.accent),
            SizedBox(height: tokens.spaceLg),
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: tokens.spaceXs),
            AppStatus(label: label, tone: tone),
          ],
        ),
      ),
    );
  }
}

final class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spaceSm),
        child: Row(
          children: <Widget>[
            Icon(icon, color: tokens.danger),
            SizedBox(width: tokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

final class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CoordinatorEvent event;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.bolt_rounded, color: tokens.info, size: 20),
          SizedBox(width: tokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(event.message ?? event.code ?? event.kind),
                Text(
                  event.occurredAt.toLocal().toString(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
