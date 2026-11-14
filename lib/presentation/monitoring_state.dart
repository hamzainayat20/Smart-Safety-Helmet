import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'components/state_view.dart';
import 'design_system/safety_status.dart';

/// Indicator colour for [state] on light surfaces (≥ 3:1), from the design
/// system's status roles. Pair it with [monitoringStateIcon] and a text label.
Color monitoringStateColor(MonitoringState state) =>
    safetyStatusForMonitoringState(state).palette.strong;

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

  StateViewKind get _kind => switch (state) {
    MonitoringState.loading => StateViewKind.loading,
    MonitoringState.permissionDenied => StateViewKind.permissionDenied,
    MonitoringState.backendError => StateViewKind.error,
    MonitoringState.offline => StateViewKind.offline,
    MonitoringState.stale => StateViewKind.stale,
    _ => StateViewKind.empty,
  };

  @override
  Widget build(BuildContext context) => StateView(
    kind: _kind,
    title: title,
    message: message ?? monitoringStateDescription(state),
    onAction: onRetry,
  );
}

IconData alertTypeIcon(AlertType type) => switch (type) {
  AlertType.temperature => Icons.thermostat_rounded,
  AlertType.humidity => Icons.water_drop_outlined,
  AlertType.battery => Icons.battery_alert_rounded,
  AlertType.fall => Icons.personal_injury_outlined,
  AlertType.sensorFault => Icons.sensors_off_outlined,
  AlertType.connectivity => Icons.wifi_off_outlined,
  AlertType.gas => Icons.air_rounded,
};
