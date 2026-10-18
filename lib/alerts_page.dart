import 'package:flutter/material.dart';

import 'alert_detail_screen.dart';
import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF4F6FA),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: _buildBody(context),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildBody(BuildContext context) {
    if (viewModel.loadState == MonitoringState.loading) {
      return const Center(child: CircularProgressIndicator());
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
      return const Center(child: Text('No alerts in your assigned scope.'));
    }
    final alerts = _filteredAlerts();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _filters(),
        const SizedBox(height: 14),
        if (alerts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: Text('No alerts match these filters.')),
          )
        else
          ...alerts.map(
            (alert) => _AlertCard(
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

  Widget _filters() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _FilterMenu<AlertType?>(
        label: 'Type',
        value: _type,
        entries: [
          const DropdownMenuEntry(value: null, label: 'All types'),
          ...AlertType.values.map(
            (type) =>
                DropdownMenuEntry(value: type, label: alertTypeLabel(type)),
          ),
        ],
        onSelected: (value) => setState(() => _type = value),
      ),
      _FilterMenu<_StatusFilter>(
        label: 'Status',
        value: _status,
        entries: _StatusFilter.values
            .map(
              (value) => DropdownMenuEntry(
                value: value,
                label: value.name == 'all'
                    ? 'All statuses'
                    : value.name[0].toUpperCase() + value.name.substring(1),
              ),
            )
            .toList(growable: false),
        onSelected: (value) => setState(() => _status = value),
      ),
      _FilterMenu<_DateFilter>(
        label: 'Date',
        value: _date,
        entries: const [
          DropdownMenuEntry(value: _DateFilter.all, label: 'Any date'),
          DropdownMenuEntry(value: _DateFilter.today, label: 'Last 24 hours'),
          DropdownMenuEntry(value: _DateFilter.sevenDays, label: 'Last 7 days'),
          DropdownMenuEntry(
            value: _DateFilter.thirtyDays,
            label: 'Last 30 days',
          ),
        ],
        onSelected: (value) => setState(() => _date = value),
      ),
    ],
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
    final today = viewModel.alerts
        .where(
          (alert) =>
              DateTime.now()
                  .toUtc()
                  .difference(alert.serverReceivedAt)
                  .inHours <
              24,
        )
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Alert Centre',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              IconButton(
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                '$active active • $today today • ${viewModel.dataSourceLabel}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
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
    final color = resolved
        ? Colors.grey
        : alert.severity == SafetySeverity.critical
        ? Colors.red
        : Colors.orange;
    final evidence = alert.sensorValue == null || alert.unit == null
        ? 'Evidence available in incident record'
        : '${formatMeasurement(alert.sensorValue, alert.unit!)}'
              '${alert.threshold == null ? '' : ' (threshold: ${formatMeasurement(alert.threshold, alert.unit!)})'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(alert.type), color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${alertTypeLabel(alert.type)} — $worker',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: resolved ? Colors.grey : Colors.black,
                    ),
                  ),
                ),
                Text(
                  formatRelativeTime(alert.serverReceivedAt),
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$evidence • Helmet ${alert.helmetId} • ${helmet?.zone ?? 'Zone unavailable'} • ${alert.status.name}',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.6),
                fontSize: 12,
                height: 1.3,
              ),
            ),
            if (!resolved) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton(
                    key: Key('acknowledge-${alert.alertId}'),
                    onPressed: acknowledged || acknowledging
                        ? null
                        : () => _acknowledge(context),
                    child: Text(
                      acknowledged
                          ? 'Acknowledged'
                          : acknowledging
                          ? 'Confirming...'
                          : 'Acknowledge',
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onOpen,
                    child: const Text('View Details'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _acknowledge(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Acknowledge alert?'),
        content: const Text(
          'This records that you have seen the incident. It does not mark the physical hazard as resolved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await viewModel.acknowledge(alert.alertId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Alert acknowledged.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Acknowledgement failed: $error')),
        );
      }
    }
  }
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.value,
    required this.entries,
    required this.onSelected,
  });

  final String label;
  final T value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => DropdownMenu<T>(
    label: Text(label),
    initialSelection: value,
    dropdownMenuEntries: entries,
    onSelected: (value) {
      if (value != null || null is T) onSelected(value as T);
    },
    width: 160,
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  );
}

IconData _iconFor(AlertType type) => switch (type) {
  AlertType.temperature => Icons.thermostat_rounded,
  AlertType.humidity => Icons.water_drop_outlined,
  AlertType.battery => Icons.battery_alert_rounded,
  AlertType.fall => Icons.personal_injury_outlined,
  AlertType.sensorFault => Icons.sensors_off_outlined,
  AlertType.connectivity => Icons.wifi_off_outlined,
  AlertType.gas => Icons.warning_amber_rounded,
};
