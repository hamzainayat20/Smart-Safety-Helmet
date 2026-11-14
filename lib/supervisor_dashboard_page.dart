import 'package:flutter/material.dart';

import 'alert_detail_screen.dart';
import 'application/dashboard_view_model.dart';
import 'application/gps_map_view_model.dart';
import 'domain/models.dart';
import 'presentation/alert_actions.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';
import 'sensor_detail_screen.dart';

class SupervisorDashboardPage extends StatelessWidget {
  const SupervisorDashboardPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
    this.onLocate,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  /// Centres the GPS map on a position; the shell switches to the map tab.
  final ValueChanged<MapFocusRequest>? onLocate;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(child: ContentSheet(child: _buildBody(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final profile = viewModel.profile;
    return AppPageHeader(
      eyebrow: 'WELCOME BACK',
      title: profile.displayName,
      titleSuffix: const RoleTag(label: 'Supervisor'),
      subtitle:
          'Site: ${profile.organizationName ?? 'Not assigned'} • ${viewModel.dataSourceLabel}',
      actions: [
        HeaderIconButton(
          icon: Icons.logout_rounded,
          tooltip: 'Sign out',
          onPressed: onSignOut,
        ),
      ],
      bottom: Align(
        alignment: Alignment.centerLeft,
        child: ConnectionIndicator(
          sourceLabel: viewModel.dataSourceLabel,
          connected: viewModel.backendConnected,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (viewModel.loadState == MonitoringState.loading) {
      return const StateView(
        kind: StateViewKind.loading,
        title: 'Loading site data',
        message: 'Connecting to your assigned helmets…',
      );
    }
    if (viewModel.loadState == MonitoringState.permissionDenied ||
        viewModel.loadState == MonitoringState.backendError) {
      return MonitoringStatePanel(
        state: viewModel.loadState,
        title: viewModel.loadState == MonitoringState.permissionDenied
            ? 'Monitoring permission denied'
            : 'Monitoring backend unavailable',
        message: viewModel.errorMessage,
        onRetry: viewModel.retry,
      );
    }
    if (viewModel.helmets.isEmpty) {
      return const MonitoringStatePanel(
        state: MonitoringState.empty,
        title: 'No assigned helmets',
        message: 'No helmets are assigned to this supervisor.',
      );
    }

    final attention = _attentionAlerts();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _SiteOverview(viewModel: viewModel),
        const SizedBox(height: AppSpacing.md),
        _buildKpis(),
        if (attention.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            title: 'Act now',
            subtitle: 'Open alerts awaiting acknowledgement',
            trailing: StatusChip(
              status: SafetyStatus.critical,
              label: '${attention.length} open',
            ),
          ),
          for (final alert in attention)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _AttentionTile(
                alert: alert,
                workerName: _workerFor(alert),
                onAcknowledge: () => confirmAndAcknowledgeAlert(
                  context,
                  viewModel: viewModel,
                  alertId: alert.alertId,
                ),
                onLocate: _locateAction(alert),
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AlertDetailScreen(
                      profile: viewModel.profile,
                      alertId: alert.alertId,
                      dependencies: viewModel.dependencies,
                    ),
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(
          title: 'Worker Status',
          trailing: Text(
            '${viewModel.helmets.length} assigned',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        for (final helmet in viewModel.sortedHelmets)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _WorkerTile(
              name: viewModel.workerNameFor(helmet),
              details:
                  '${viewModel.siteNameFor(helmet)} • ${helmet.zone ?? 'Zone unavailable'} • '
                  'Helmet #${helmet.helmetId}',
              updated: viewModel.lastUpdateFor(helmet) == null
                  ? 'Never updated'
                  : 'Last update ${formatRelativeTime(viewModel.lastUpdateFor(helmet)!)}',
              statusLabel: viewModel.stateLabelFor(helmet),
              status: safetyStatusForMonitoringState(
                viewModel.monitoringStateFor(helmet),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SensorDetailScreen(
                    helmetId: helmet.helmetId,
                    workerName: viewModel.workerNameFor(helmet),
                    viewModel: viewModel,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildKpis() {
    final live = viewModel.statisticsAreLive;
    return ResponsiveTileGrid(
      minTileWidth: 150,
      children: [
        MetricTile(
          label: 'Workers Online',
          value: live ? '${viewModel.onlineHelmetCount}' : null,
          suffix: '/${viewModel.activeHelmets.length}',
          icon: Icons.wifi_tethering_rounded,
          status: SafetyStatus.normal,
        ),
        MetricTile(
          label: 'Active Alerts',
          value: live ? '${viewModel.activeAlertCount}' : null,
          icon: Icons.notification_important_outlined,
          status: live && viewModel.activeAlertCount > 0
              ? SafetyStatus.critical
              : null,
        ),
        MetricTile(
          label: 'Helmets Active',
          value: live ? '${viewModel.activeHelmets.length}' : null,
          icon: Icons.engineering_outlined,
        ),
        MetricTile(
          label: 'Low Battery',
          value: live ? '${viewModel.lowBatteryCount}' : null,
          icon: Icons.battery_alert_rounded,
          status: live && viewModel.lowBatteryCount > 0
              ? SafetyStatus.warning
              : null,
        ),
      ],
    );
  }

  /// Unacknowledged, unresolved alerts — critical first, newest first, max 3.
  List<SafetyAlert> _attentionAlerts() {
    final open = viewModel.alerts
        .where(
          (alert) =>
              alert.status != AlertStatus.acknowledged &&
              alert.status != AlertStatus.resolved,
        )
        .toList();
    open.sort((a, b) {
      final aCritical = a.severity == SafetySeverity.critical ? 1 : 0;
      final bCritical = b.severity == SafetySeverity.critical ? 1 : 0;
      if (aCritical != bCritical) return bCritical.compareTo(aCritical);
      return b.serverReceivedAt.compareTo(a.serverReceivedAt);
    });
    return open.take(3).toList(growable: false);
  }

  VoidCallback? _locateAction(SafetyAlert alert) {
    final locate = onLocate;
    final location = alert.location;
    if (locate == null || location == null) return null;
    return () => locate(
      MapFocusRequest.worker(helmetId: alert.helmetId, location: location),
    );
  }

  String _workerFor(SafetyAlert alert) {
    for (final helmet in viewModel.helmets) {
      if (helmet.helmetId == alert.helmetId) {
        return viewModel.workerNameFor(helmet);
      }
    }
    return 'Unassigned';
  }
}

/// Live breakdown of every assigned helmet by safety state.
class _SiteOverview extends StatelessWidget {
  const _SiteOverview({required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final counts = <SafetyStatus, int>{};
    for (final helmet in viewModel.helmets) {
      final status = safetyStatusForMonitoringState(
        viewModel.monitoringStateFor(helmet),
      );
      final bucket = switch (status) {
        SafetyStatus.normal => SafetyStatus.normal,
        SafetyStatus.warning || SafetyStatus.pending => SafetyStatus.warning,
        SafetyStatus.critical => SafetyStatus.critical,
        _ => SafetyStatus.offline,
      };
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    final total = viewModel.helmets.length;
    final normal = counts[SafetyStatus.normal] ?? 0;
    final warning = counts[SafetyStatus.warning] ?? 0;
    final atRisk = counts[SafetyStatus.critical] ?? 0;
    final silent = counts[SafetyStatus.offline] ?? 0;

    final headlineStatus = atRisk > 0
        ? SafetyStatus.critical
        : warning > 0
        ? SafetyStatus.warning
        : normal == total
        ? SafetyStatus.normal
        : SafetyStatus.offline;
    final headline = atRisk > 0
        ? '$atRisk ${atRisk == 1 ? 'worker' : 'workers'} at risk'
        : warning > 0
        ? '$warning ${warning == 1 ? 'worker needs' : 'workers need'} attention'
        : normal == total
        ? 'All workers within safe limits'
        : '$silent ${silent == 1 ? 'helmet is' : 'helmets are'} not reporting';
    final segments = [
      (SafetyStatus.normal, normal, 'Safe'),
      (SafetyStatus.warning, warning, 'Attention'),
      (SafetyStatus.critical, atRisk, 'At risk'),
      (SafetyStatus.offline, silent, 'No live data'),
    ];

    return AppCard(
      status: headlineStatus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SITE SAFETY OVERVIEW',
            style: AppTypography.overline.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                headlineStatus.icon,
                size: AppSizes.iconLg,
                color: headlineStatus.palette.strong,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    headline,
                    style: AppTypography.title.copyWith(
                      color: headlineStatus.palette.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final (status, count, _) in segments)
                      if (count > 0)
                        Expanded(
                          flex: count,
                          child: Container(
                            margin: const EdgeInsets.only(right: 2),
                            color: status.palette.strong,
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (status, count, label) in segments)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      status.icon,
                      size: AppSizes.iconSm,
                      color: status.palette.strong,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '$count $label',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.alert,
    required this.workerName,
    required this.onOpen,
    required this.onAcknowledge,
    this.onLocate,
  });

  final SafetyAlert alert;
  final String workerName;
  final VoidCallback onOpen;
  final VoidCallback onAcknowledge;

  /// Null when the alert has no position or the map is not available.
  final VoidCallback? onLocate;

  @override
  Widget build(BuildContext context) {
    final status = safetyStatusForSeverity(alert.severity);
    return AppCard(
      status: status,
      onTap: onOpen,
      semanticLabel:
          '${alertTypeLabel(alert.type)} alert for $workerName, ${status.label}. Open details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: alertTypeIcon(alert.type), status: status),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alertTypeLabel(alert.type)} — $workerName',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyStrong.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Helmet ${alert.helmetId} • ${formatRelativeTime(alert.serverReceivedAt)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: Key('attention-acknowledge-${alert.alertId}'),
                  label: 'Acknowledge',
                  icon: Icons.done_rounded,
                  onPressed: onAcknowledge,
                ),
              ),
              if (onLocate != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    key: Key('attention-locate-${alert.alertId}'),
                    label: 'Locate',
                    icon: Icons.my_location_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: onLocate,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkerTile extends StatelessWidget {
  const _WorkerTile({
    required this.name,
    required this.details,
    required this.updated,
    required this.statusLabel,
    required this.status,
    required this.onTap,
  });

  final String name;
  final String details;
  final String updated;
  final String statusLabel;
  final SafetyStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    status: status.needsAttention ? status : null,
    child: Row(
      children: [
        InitialsAvatar(name: name, status: status),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyStrong.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                details,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                updated,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StatusChip(status: status, label: statusLabel),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      ],
    ),
  );
}
