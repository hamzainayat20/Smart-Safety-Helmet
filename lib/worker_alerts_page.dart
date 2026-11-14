import 'package:flutter/material.dart';

import 'alert_detail_screen.dart';
import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';

class WorkerAlertsPage extends StatefulWidget {
  const WorkerAlertsPage({super.key, required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  State<WorkerAlertsPage> createState() => _WorkerAlertsPageState();
}

enum _WorkerAlertFilter { all, active, resolved }

class _WorkerAlertsPageState extends State<WorkerAlertsPage> {
  _WorkerAlertFilter _filter = _WorkerAlertFilter.all;

  DashboardViewModel get viewModel => widget.viewModel;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final active = viewModel.alerts
          .where((alert) => alert.status != AlertStatus.resolved)
          .length;
      final now = DateTime.now().toUtc();
      final today = viewModel.alerts
          .where(
            (alert) => now.difference(alert.serverReceivedAt).inHours < 24,
          )
          .length;
      return Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPageHeader(
                eyebrow: 'INCIDENTS',
                title: 'My Alerts',
                subtitle:
                    '${viewModel.helmets.firstOrNull?.helmetId ?? 'No helmet'} • '
                    '${viewModel.profile.displayName} • ${viewModel.dataSourceLabel}',
                bottom: Text(
                  '$active active • $today today • '
                  '${viewModel.alerts.length - active} closed • '
                  '${viewModel.alerts.length} total',
                  style: AppTypography.label.copyWith(
                    color: AppColors.onInkMuted,
                  ),
                ),
              ),
              Expanded(
                child: ContentSheet(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    children: [
                      SegmentedFilter<_WorkerAlertFilter>(
                        values: _WorkerAlertFilter.values,
                        selected: _filter,
                        labelOf: (value) => switch (value) {
                          _WorkerAlertFilter.all => 'All',
                          _WorkerAlertFilter.active => 'Active',
                          _WorkerAlertFilter.resolved => 'Resolved',
                        },
                        onSelected: (value) => setState(() => _filter = value),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ..._content(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _content(BuildContext context) {
    if (viewModel.loadState == MonitoringState.loading) {
      return const [
        StateView(
          kind: StateViewKind.loading,
          title: 'Loading alerts',
          message: 'Fetching alerts for your helmet…',
        ),
      ];
    }
    if (viewModel.loadState == MonitoringState.permissionDenied ||
        viewModel.loadState == MonitoringState.backendError) {
      return [
        MonitoringStatePanel(
          state: viewModel.loadState,
          title: viewModel.loadState == MonitoringState.permissionDenied
              ? 'Alert permission denied'
              : 'Alert backend unavailable',
          message: viewModel.errorMessage,
          onRetry: viewModel.retry,
        ),
      ];
    }
    final alerts = _filteredAlerts;
    if (alerts.isEmpty) {
      return const [
        StateView(
          kind: StateViewKind.empty,
          title: 'Nothing to show',
          message: 'No alerts match this filter for your assigned helmet.',
        ),
      ];
    }
    return [
      for (final alert in alerts)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _WorkerAlertCard(
            alert: alert,
            onOpen: () => _openAlert(context, alert.alertId),
          ),
        ),
    ];
  }

  List<SafetyAlert> get _filteredAlerts => viewModel.alerts
      .where((alert) {
        return switch (_filter) {
          _WorkerAlertFilter.all => true,
          _WorkerAlertFilter.active => alert.status != AlertStatus.resolved,
          _WorkerAlertFilter.resolved => alert.status == AlertStatus.resolved,
        };
      })
      .toList(growable: false);

  void _openAlert(BuildContext context, String alertId) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AlertDetailScreen(
          profile: viewModel.profile,
          alertId: alertId,
          dependencies: viewModel.dependencies,
        ),
      ),
    );
  }
}

class _WorkerAlertCard extends StatelessWidget {
  const _WorkerAlertCard({required this.alert, required this.onOpen});

  final SafetyAlert alert;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final resolved = alert.status == AlertStatus.resolved;
    final status = resolved
        ? SafetyStatus.normal
        : safetyStatusForSeverity(alert.severity);
    final detail = alert.sensorValue == null || alert.unit == null
        ? 'Incident evidence recorded'
        : '${formatMeasurement(alert.sensorValue, alert.unit!)}'
              '${alert.threshold == null ? '' : ' (threshold: ${formatMeasurement(alert.threshold, alert.unit!)})'}';
    return AppCard(
      status: resolved ? null : status,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: resolved
                    ? Icons.check_circle_outline_rounded
                    : alertTypeIcon(alert.type),
                status: status,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alertTypeLabel(alert.type)}${resolved ? ' — Resolved' : ''}',
                      style: AppTypography.bodyStrong.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Helmet ${alert.helmetId} • ${formatRelativeTime(alert.serverReceivedAt)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          StatusChip(
            status: status,
            label: resolved ? 'Closed' : status.label,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            detail,
            style: AppTypography.label.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: AppSizes.iconMd),
              label: const Text('View details'),
            ),
          ),
        ],
      ),
    );
  }
}
