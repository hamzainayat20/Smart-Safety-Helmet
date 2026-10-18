import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';

class WorkerDashboardPage extends StatelessWidget {
  const WorkerDashboardPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final helmet = viewModel.helmets.firstOrNull;
      final reading = helmet == null
          ? null
          : viewModel.readingFor(helmet.helmetId);
      final monitoringState = helmet == null
          ? MonitoringState.empty
          : viewModel.monitoringStateFor(helmet);
      final state = helmet == null
          ? 'Unassigned'
          : viewModel.stateLabelFor(helmet);
      final stateColor = monitoringStateColor(monitoringState);
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
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
                child: viewModel.loadState == MonitoringState.loading
                    ? const Center(child: CircularProgressIndicator())
                    : viewModel.loadState == MonitoringState.permissionDenied ||
                          viewModel.loadState == MonitoringState.backendError
                    ? MonitoringStatePanel(
                        state: viewModel.loadState,
                        title:
                            viewModel.loadState ==
                                MonitoringState.permissionDenied
                            ? 'Monitoring permission denied'
                            : 'Monitoring backend unavailable',
                        message: viewModel.errorMessage,
                        onRetry: viewModel.retry,
                      )
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  monitoringStateIcon(monitoringState),
                                  color: stateColor,
                                  size: 60,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  helmet == null
                                      ? 'No helmet assigned'
                                      : 'Status: ${state.toUpperCase()}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: stateColor,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  helmet == null
                                      ? 'Contact your supervisor for an assignment.'
                                      : monitoringStateDescription(
                                          monitoringState,
                                        ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    fontSize: 12,
                                  ),
                                ),
                                if (helmet != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    viewModel.lastUpdateFor(helmet) == null
                                        ? 'No update has been received'
                                        : 'Last update ${formatRelativeTime(viewModel.lastUpdateFor(helmet)!)} • ${viewModel.dataSourceLabel}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (helmet != null) ...[
                            const SizedBox(height: 20),
                            Text(
                              'Your Helmet Status • ${helmet.helmetId}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 15),
                            _StatusRow(
                              label: 'Battery',
                              value: formatMeasurement(
                                reading?.batteryPct,
                                SensorUnit.percent,
                                fractionDigits: 0,
                              ),
                              icon: Icons.battery_full,
                              color: reading?.batteryPct == null
                                  ? Colors.grey
                                  : Colors.green,
                            ),
                            _StatusRow(
                              label: 'Humidity',
                              value: formatMeasurement(
                                reading?.humidityPct,
                                SensorUnit.percentRelativeHumidity,
                              ),
                              icon: Icons.water_drop,
                              color: const Color(0xFF2F80ED),
                            ),
                            _StatusRow(
                              label: 'Temperature',
                              value: formatMeasurement(
                                reading?.temperatureC,
                                SensorUnit.degreesCelsius,
                              ),
                              icon: Icons.thermostat,
                              color: Colors.orange,
                            ),
                            _StatusRow(
                              label: reading?.gasWarmUp == true
                                  ? 'Gas Level • Warming Up'
                                  : 'Gas Level',
                              value: formatMeasurement(
                                reading?.gasPpm,
                                SensorUnit.partsPerMillion,
                              ),
                              icon: Icons.cloud,
                              color: const Color(0xFF2F80ED),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(25, 20, 25, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Welcome back,',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            IconButton(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout, color: Colors.white, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              viewModel.profile.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              ' — Worker',
              style: TextStyle(
                color: Color(0xFF2F80ED),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Text(
          'Site: ${viewModel.profile.organizationName ?? 'Not assigned'}',
          style: const TextStyle(
            color: Color(0xFF2F80ED),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 15),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ],
    ),
  );
}
