import 'package:flutter/material.dart';

import 'alert_detail_screen.dart';
import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
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
      return Scaffold(
        backgroundColor: const Color(0xFF07152C),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Alerts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${viewModel.helmets.firstOrNull?.helmetId ?? 'No helmet'} • '
                      '${viewModel.profile.displayName} • ${viewModel.dataSourceLabel}',
                      style: const TextStyle(
                        color: Color(0xFF77A6D7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StatMini(
                          label: 'Active',
                          value: '$active',
                          color: Colors.red,
                        ),
                        _StatMini(
                          label: 'Today',
                          value: '$today',
                          color: Colors.orange,
                        ),
                        _StatMini(
                          label: 'Resolved',
                          value: '${viewModel.alerts.length - active}',
                          color: Colors.green,
                        ),
                        _StatMini(
                          label: 'Total',
                          value: '${viewModel.alerts.length}',
                          color: Colors.blue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _filterTabs(),
                      const SizedBox(height: 20),
                      if (viewModel.loadState == MonitoringState.loading)
                        const Center(child: CircularProgressIndicator())
                      else if (viewModel.loadState ==
                              MonitoringState.permissionDenied ||
                          viewModel.loadState == MonitoringState.backendError)
                        MonitoringStatePanel(
                          state: viewModel.loadState,
                          title:
                              viewModel.loadState ==
                                  MonitoringState.permissionDenied
                              ? 'Alert permission denied'
                              : 'Alert backend unavailable',
                          message: viewModel.errorMessage,
                          onRetry: viewModel.retry,
                        )
                      else if (_filteredAlerts.isEmpty)
                        const Text(
                          'No alerts match this filter for your assigned helmet.',
                        )
                      else
                        ..._filteredAlerts.map(
                          (alert) => _WorkerAlertCard(
                            alert: alert,
                            onOpen: () => _openAlert(context, alert.alertId),
                          ),
                        ),
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

  List<SafetyAlert> get _filteredAlerts => viewModel.alerts
      .where((alert) {
        return switch (_filter) {
          _WorkerAlertFilter.all => true,
          _WorkerAlertFilter.active => alert.status != AlertStatus.resolved,
          _WorkerAlertFilter.resolved => alert.status == AlertStatus.resolved,
        };
      })
      .toList(growable: false);

  Widget _filterTabs() => Row(
    children: _WorkerAlertFilter.values.indexed
        .expand((entry) {
          final (index, value) = entry;
          return [
            if (index > 0) const SizedBox(width: 8),
            _FilterTab(
              label: value.name[0].toUpperCase() + value.name.substring(1),
              isSelected: _filter == value,
              onTap: () => setState(() => _filter = value),
            ),
          ];
        })
        .toList(growable: false),
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
}

class _StatMini extends StatelessWidget {
  const _StatMini({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 75,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF16324F),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.black : Colors.black54,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    ),
  );
}

class _WorkerAlertCard extends StatelessWidget {
  const _WorkerAlertCard({required this.alert, required this.onOpen});
  final SafetyAlert alert;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final resolved = alert.status == AlertStatus.resolved;
    final color = resolved
        ? Colors.green
        : alert.severity == SafetySeverity.critical
        ? Colors.red
        : Colors.orange;
    final detail = alert.sensorValue == null || alert.unit == null
        ? 'Incident evidence recorded'
        : '${formatMeasurement(alert.sensorValue, alert.unit!)}'
              '${alert.threshold == null ? '' : ' (threshold: ${formatMeasurement(alert.threshold, alert.unit!)})'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                resolved
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${alertTypeLabel(alert.type)}${resolved ? ' — Resolved' : ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                formatRelativeTime(alert.serverReceivedAt),
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Helmet ${alert.helmetId} • ${alert.status.name}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            detail,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onOpen,
              child: const Text('View Details'),
            ),
          ),
        ],
      ),
    );
  }
}
