import 'package:flutter/material.dart';

import '../domain/models.dart';

Color monitoringStateColor(MonitoringState state) => switch (state) {
  MonitoringState.safe => Colors.green,
  MonitoringState.warning || MonitoringState.warmingUp => Colors.orange,
  MonitoringState.critical || MonitoringState.sensorFault => Colors.red,
  MonitoringState.permissionDenied => const Color(0xFF9B1C1C),
  MonitoringState.backendError => const Color(0xFF8A4B08),
  _ => Colors.grey,
};

IconData monitoringStateIcon(MonitoringState state) => switch (state) {
  MonitoringState.loading => Icons.hourglass_top_rounded,
  MonitoringState.empty => Icons.inbox_outlined,
  MonitoringState.safe => Icons.check_circle_rounded,
  MonitoringState.warning => Icons.warning_amber_rounded,
  MonitoringState.critical => Icons.error_rounded,
  MonitoringState.stale => Icons.schedule_rounded,
  MonitoringState.offline => Icons.wifi_off_rounded,
  MonitoringState.sensorFault => Icons.sensors_off_rounded,
  MonitoringState.warmingUp => Icons.timer_outlined,
  MonitoringState.permissionDenied => Icons.lock_outline_rounded,
  MonitoringState.backendError => Icons.cloud_off_outlined,
};

String monitoringStateDescription(MonitoringState state) => switch (state) {
  MonitoringState.loading => 'Loading authorized monitoring data…',
  MonitoringState.empty => 'No live data is available for this assignment.',
  MonitoringState.safe => 'Latest validated readings are within safe limits.',
  MonitoringState.warning =>
    'A threshold is approaching or connectivity is degraded.',
  MonitoringState.critical => 'Immediate action is required.',
  MonitoringState.stale =>
    'Values are last known and are not being presented as live.',
  MonitoringState.offline =>
    'Helmet unavailable. Local safety alerts remain independent of the app.',
  MonitoringState.sensorFault =>
    'A sensor fault is active; unavailable values are not treated as safe.',
  MonitoringState.warmingUp =>
    'Gas diagnostics are excluded from hazard classification until ready.',
  MonitoringState.permissionDenied =>
    'Your account is not authorized for this monitoring data.',
  MonitoringState.backendError =>
    'The monitoring backend could not be reached. Try again.',
};

class MonitoringStatePanel extends StatelessWidget {
  const MonitoringStatePanel({
    super.key,
    required this.state,
    required this.title,
    this.message,
    this.onRetry,
  });

  final MonitoringState state;
  final String title;
  final String? message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              monitoringStateIcon(state),
              color: monitoringStateColor(state),
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              message ?? monitoringStateDescription(state),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.35),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    ),
  );
}
