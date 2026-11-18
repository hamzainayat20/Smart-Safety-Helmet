import 'package:flutter/material.dart';

import 'alert_detail_screen.dart';
import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/alert_actions.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

enum _StatusFilter {
  all,
  active,
  created,
  delivered,
  viewed,
  acknowledged,
  resolved,
}

enum _DateFilter { all, today, sevenDays, thirtyDays }

class _AlertsPageState extends State<AlertsPage> {
  AlertType? _type;
  _StatusFilter _status = _StatusFilter.all;
  _DateFilter _date = _DateFilter.all;

  DashboardViewModel get viewModel => widget.viewModel;

  bool get _hasFilters =>
      _type != null || _status != _StatusFilter.all || _date != _DateFilter.all;

  void _clearFilters() => setState(() {
    _type = null;
    _status = _StatusFilter.all;
    _date = _DateFilter.all;
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
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

  Widget _buildBody(BuildContext context) {
    if (viewModel.loadState == MonitoringState.loading) {
      return const StateView(
        kind: StateViewKind.loading,
        title: 'Loading alerts',
        message: 'Fetching alerts for your assigned helmets…',
      );
    }
    if (viewModel.loadState == MonitoringState.permissionDenied ||
        viewModel.loadState == MonitoringState.backendError) {
      return MonitoringStatePanel(
        state: viewModel.loadState,
        title: viewModel.loadState == MonitoringState.permissionDenied
            ? 'Alert permission denied'
            : 'Alert backend unavailable',
        message: viewModel.errorMessage,
        onRetry: viewModel.retry,
      );
    }
    if (viewModel.alerts.isEmpty) {
      return const StateView(
        kind: StateViewKind.empty,
        title: 'No alerts',
        message: 'No alerts in your assigned scope.',
      );
    }
    final alerts = _filteredAlerts();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        _filters(),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Showing ${alerts.length} of ${viewModel.alerts.length}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_hasFilters)
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(
                  Icons.filter_alt_off_outlined,
                  size: AppSizes.iconMd,
                ),
                label: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (alerts.isEmpty)
          StateView(
            kind: StateViewKind.empty,
            title: 'Nothing matches',
            message: 'No alerts match these filters.',
            actionLabel: 'Clear filters',
            onAction: _clearFilters,
          )
        else
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _AlertCard(
                alert: alert,
                viewModel: viewModel,
                onOpen: () => _openAlert(context, alert.alertId),
              ),
            ),
      ],
    );
  }

  List<SafetyAlert> _filteredAlerts() {
    final now = DateTime.now().toUtc();
    return viewModel.alerts
        .where((alert) {
          if (_type != null && alert.type != _type) return false;
          final statusMatches = switch (_status) {
            _StatusFilter.all => true,
            _StatusFilter.active => alert.status != AlertStatus.resolved,
            _StatusFilter.created => alert.status == AlertStatus.created,
            _StatusFilter.delivered => alert.status == AlertStatus.delivered,
            _StatusFilter.viewed => alert.status == AlertStatus.viewed,
            _StatusFilter.acknowledged =>
              alert.status == AlertStatus.acknowledged,
            _StatusFilter.resolved => alert.status == AlertStatus.resolved,
          };
          if (!statusMatches) return false;
          final age = now.difference(alert.serverReceivedAt);
          return switch (_date) {
            _DateFilter.all => true,
            _DateFilter.today => age <= const Duration(days: 1),
            _DateFilter.sevenDays => age <= const Duration(days: 7),
            _DateFilter.thirtyDays => age <= const Duration(days: 30),
          };
        })
        .toList(growable: false);
  }

  Widget _filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        FilterMenu<AlertType?>(
          label: 'Type',
          value: _type,
          entries: [
            (null, 'All types'),
            for (final type in AlertType.values) (type, alertTypeLabel(type)),
          ],
          onSelected: (value) => setState(() => _type = value),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilterMenu<_StatusFilter>(
          label: 'Status',
          value: _status,
          entries: const [
            (_StatusFilter.all, 'All statuses'),
            (_StatusFilter.active, 'Active'),
            (_StatusFilter.created, 'Created'),
            (_StatusFilter.delivered, 'Delivered'),
            (_StatusFilter.viewed, 'Viewed'),
            (_StatusFilter.acknowledged, 'Acknowledged'),
            (_StatusFilter.resolved, 'Resolved'),
          ],
          onSelected: (value) => setState(() => _status = value),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilterMenu<_DateFilter>(
          label: 'Date',
          value: _date,
          entries: const [
            (_DateFilter.all, 'Any date'),
            (_DateFilter.today, 'Last 24 hours'),
            (_DateFilter.sevenDays, 'Last 7 days'),
            (_DateFilter.thirtyDays, 'Last 30 days'),
          ],
          onSelected: (value) => setState(() => _date = value),
        ),
      ],
    ),
  );

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

  Widget _buildHeader() {
    final active = viewModel.activeAlertCount;
    final now = DateTime.now().toUtc();
    final today = viewModel.alerts
        .where((alert) => now.difference(alert.serverReceivedAt).inHours < 24)
        .length;
    final resolved = viewModel.alerts
        .where((alert) => alert.status == AlertStatus.resolved)
        .length;
    return AppPageHeader(
      title: 'Alert Centre',
      compact: true,
      subtitle: '$active active • $today today • ${viewModel.dataSourceLabel}',
      actions: [
        HeaderIconButton(
          icon: Icons.logout_rounded,
          tooltip: 'Sign out',
          onPressed: widget.onSignOut,
        ),
      ],
      bottom: Text(
        '$resolved closed • ${viewModel.alerts.length} total',
        style: AppTypography.label.copyWith(color: AppColors.onInkMuted),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.viewModel,
    required this.onOpen,
  });

  final SafetyAlert alert;
  final DashboardViewModel viewModel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final helmet = viewModel.helmets
        .where((item) => item.helmetId == alert.helmetId)
        .firstOrNull;
    final worker = helmet == null
        ? 'Unassigned'
        : viewModel.workerNameFor(helmet);
    final resolved = alert.status == AlertStatus.resolved;
    final acknowledged =
        alert.status == AlertStatus.acknowledged ||
        alert.acknowledgedAt != null;
    final acknowledging = viewModel.isAcknowledging(alert.alertId);
    final status = resolved
        ? SafetyStatus.unknown
        : safetyStatusForSeverity(alert.severity);
    final evidence = alert.sensorValue == null || alert.unit == null
        ? 'Evidence available in incident record'
        : '${formatMeasurement(alert.sensorValue, alert.unit!)}'
              '${alert.threshold == null ? '' : ' (threshold: ${formatMeasurement(alert.threshold, alert.unit!)})'}';

    return AppCard(
      status: resolved ? null : status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: alertTypeIcon(alert.type), status: status),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alertTypeLabel(alert.type)} — $worker',
                      style: AppTypography.bodyStrong.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${formatRelativeTime(alert.serverReceivedAt)} • ${formatUtcTimestamp(alert.serverReceivedAt)}',
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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusChip(
                status: status,
                label: resolved ? 'Resolved' : status.label,
              ),
              StatusChip(
                status: acknowledged || resolved
                    ? SafetyStatus.normal
                    : SafetyStatus.pending,
                label: _lifecycleLabel(alert.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '$evidence\nHelmet ${alert.helmetId} • ${helmet?.zone ?? 'Zone unavailable'}\n'
              '${formatCoordinates(alert.location)}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (!resolved) ...[
                Expanded(
                  child: AppButton(
                    key: Key('acknowledge-${alert.alertId}'),
                    label: acknowledged
                        ? 'Acknowledged'
                        : acknowledging
                        ? 'Confirming...'
                        : 'Acknowledge',
                    icon: acknowledged
                        ? Icons.task_alt_rounded
                        : Icons.done_rounded,
                    loading: acknowledging,
                    onPressed: acknowledged
                        ? null
                        : () => _acknowledge(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: AppButton(
                  label: 'View details',
                  icon: Icons.open_in_new_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: onOpen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _lifecycleLabel(AlertStatus status) => switch (status) {
    AlertStatus.created => 'Created',
    AlertStatus.delivered => 'Delivered',
    AlertStatus.viewed => 'Viewed',
    AlertStatus.acknowledged => 'Acknowledged',
    AlertStatus.resolved => 'Closed',
  };

  Future<void> _acknowledge(BuildContext context) => confirmAndAcknowledgeAlert(
    context,
    viewModel: viewModel,
    alertId: alert.alertId,
  );
}
