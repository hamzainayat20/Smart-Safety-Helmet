import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';
import 'presentation/assessment_history_panel.dart';
import 'presentation/helmet_history.dart';
import 'presentation/live_sensor_diagnostics.dart';
import 'presentation/monitoring_state.dart';
import 'presentation/safety_assessment_card.dart';
import 'presentation/sensor_limits.dart';

class SensorDetailScreen extends StatelessWidget {
  const SensorDetailScreen({
    super.key,
    required this.helmetId,
    required this.workerName,
    required this.viewModel,
  });

  final String helmetId;
  final String workerName;
  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final helmet = viewModel.helmets
          .where((item) => item.helmetId == helmetId)
          .firstOrNull;
      final reading = viewModel.readingFor(helmetId);
      final state = helmet == null
          ? viewModel.loadState
          : viewModel.monitoringStateFor(helmet);
      return Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, reading, state),
              Expanded(
                child: ContentSheet(
                  child:
                      state == MonitoringState.loading ||
                          state == MonitoringState.permissionDenied ||
                          state == MonitoringState.backendError ||
                          reading == null
                      ? MonitoringStatePanel(
                          state: state,
                          title: state == MonitoringState.permissionDenied
                              ? 'Sensor permission denied'
                              : state == MonitoringState.backendError
                              ? 'Sensor backend unavailable'
                              : reading == null
                              ? 'No current reading'
                              : 'Loading sensor data',
                          message: viewModel.errorMessage,
                          onRetry:
                              state == MonitoringState.permissionDenied ||
                                  state == MonitoringState.backendError
                              ? viewModel.retry
                              : null,
                        )
                      : HelmetLimitsBuilder(
                          viewModel: viewModel,
                          helmetId: helmetId,
                          builder: (context, limits) => HelmetHistoryBuilder(
                            viewModel: viewModel,
                            helmetId: helmetId,
                            builder: (context, history) =>
                                SingleChildScrollView(
                                  padding: EdgeInsets.fromLTRB(
                                    AppSpacing.md,
                                    AppSpacing.lg,
                                    AppSpacing.md,
                                    AppSpacing.xl +
                                        MediaQuery.paddingOf(context).bottom,
                                  ),
                                  child: _content(
                                    reading,
                                    state,
                                    limits,
                                    history,
                                  ),
                                ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildHeader(
    BuildContext context,
    SensorReading? reading,
    MonitoringState state,
  ) => AppPageHeader(
    title: 'Sensor Data',
    compact: true,
    subtitle: reading == null
        ? viewModel.dataSourceLabel
        : '$helmetId · $workerName · Received ${formatRelativeTime(reading.serverReceivedAt)} · ${viewModel.dataSourceLabel}',
    leading: HeaderIconButton(
      icon: Icons.arrow_back_rounded,
      tooltip: 'Back',
      onPressed: () => Navigator.pop(context),
    ),
    bottom: Align(
      alignment: Alignment.centerLeft,
      child: StatusChip(
        status: safetyStatusForMonitoringState(state),
        label: _stateLabel(state),
        onInk: true,
      ),
    ),
  );

  Widget _content(
    SensorReading reading,
    MonitoringState state,
    SensorLimits limits,
    List<SensorReading> history,
  ) {
    final notLive =
        state == MonitoringState.stale || state == MonitoringState.offline;
    SafetyStatus shown(SafetyStatus status) =>
        notLive ? SafetyStatus.stale : status;
    String? label(SafetyStatus status) =>
        notLive ? null : readingStatusLabel(status);

    final temperature = limits.temperature(reading.temperatureC);
    final humidity = limits.humidity(reading.humidityPct);
    final gas = limits.gas(reading.gasPpm, warmingUp: reading.gasWarmUp);
    final assessment = viewModel.assessmentFor(helmetId);
    // No heat-index thresholds exist in the requirements, so use the AI
    // service's own heat-index risk instead of inventing limits.
    final heatIndex = assessment == null
        ? SafetyStatus.pending
        : switch (assessment.heatIndexRisk) {
            ComponentRisk.normal => SafetyStatus.normal,
            ComponentRisk.warning => SafetyStatus.warning,
            ComponentRisk.critical => SafetyStatus.critical,
            ComponentRisk.unavailable => SafetyStatus.unknown,
          };
    final battery = SensorLimits.battery(reading.batteryPct);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafetyAssessmentCard(reading: reading, assessment: assessment),
        const SizedBox(height: AppSpacing.md),
        AssessmentHistoryPanel(
          repository: viewModel.dependencies.assessments,
          actor: viewModel.profile,
          helmetId: helmetId,
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(title: 'Environment', subtitle: limits.sourceLabel),
        ResponsiveTileGrid(
          minTileWidth: 160,
          children: [
            SensorCard(
              label: 'Temperature (DHT22)',
              icon: Icons.thermostat_rounded,
              value: reading.temperatureC,
              unit: SensorUnit.degreesCelsius,
              status: shown(temperature),
              statusLabel: label(temperature),
              gauge: ThresholdGauge(
                value: reading.temperatureC,
                max: limits.temperatureCriticalC * 1.2,
                warningAt: limits.temperatureWarningC,
                criticalAt: limits.temperatureCriticalC,
                status: shown(temperature),
                unit: ' °C',
              ),
              trend: TrendSparkline(
                values: trendSeries(history, (r) => r.temperatureC),
                status: shown(temperature),
                warningAt: limits.temperatureWarningC,
                unit: ' °C',
              ),
            ),
            SensorCard(
              label: 'Humidity (DHT22)',
              icon: Icons.water_drop_outlined,
              value: reading.humidityPct,
              unit: SensorUnit.percentRelativeHumidity,
              status: shown(humidity),
              statusLabel: label(humidity),
              gauge: ThresholdGauge(
                value: reading.humidityPct,
                max: 100,
                warningAt: limits.humidityWarningHighPct,
                criticalAt: limits.humidityCriticalHighPct,
                status: shown(humidity),
                unit: '%',
              ),
              trend: TrendSparkline(
                values: trendSeries(history, (r) => r.humidityPct),
                status: shown(humidity),
                warningAt: limits.humidityWarningHighPct,
                unit: '%',
              ),
            ),
            SensorCard(
              label: 'Gas Level (MQ-7)',
              icon: Icons.air_rounded,
              value: reading.gasPpm,
              unit: SensorUnit.partsPerMillion,
              status: shown(gas),
              statusLabel: label(gas),
              gauge: ThresholdGauge(
                value: reading.gasWarmUp ? null : reading.gasPpm,
                max: limits.gasCriticalPpm * 1.5,
                warningAt: limits.gasWarningPpm,
                criticalAt: limits.gasCriticalPpm,
                status: shown(gas),
                unit: ' ppm',
              ),
              trend: reading.gasWarmUp
                  ? null
                  : TrendSparkline(
                      values: trendSeries(
                        history.where((r) => !r.gasWarmUp).toList(),
                        (r) => r.gasPpm,
                      ),
                      status: shown(gas),
                      warningAt: limits.gasWarningPpm,
                      unit: ' ppm',
                    ),
            ),
            SensorCard(
              label: 'Heat index (feels like)',
              icon: Icons.wb_sunny_outlined,
              value: reading.heatIndexC,
              unit: SensorUnit.degreesCelsius,
              status: shown(heatIndex),
              statusLabel: notLive
                  ? null
                  : assessment == null
                  ? 'Awaiting assessment'
                  : readingStatusLabel(heatIndex),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Power, position and link'),
        ResponsiveTileGrid(
          minTileWidth: 160,
          children: [
            SensorCard(
              label: 'Battery',
              icon: Icons.battery_charging_full_rounded,
              value: reading.batteryPct,
              unit: SensorUnit.percent,
              fractionDigits: 0,
              status: shown(battery),
              statusLabel: label(battery),
              gauge: ThresholdGauge(
                value: reading.batteryPct?.toDouble(),
                max: 100,
                warningAt: SensorLimits.batteryWarningPct.toDouble(),
                criticalAt: SensorLimits.batteryCriticalPct.toDouble(),
                status: shown(battery),
                unit: '%',
              ),
            ),
            _TextReadingCard(
              label: 'GPS Status',
              icon: Icons.location_on_outlined,
              value: _gpsValue(reading),
              detail: _gpsStatus(reading),
              status: _gpsSafetyStatus(reading),
            ),
            _TextReadingCard(
              label: 'Helmet link',
              icon: Icons.wifi_tethering_rounded,
              value: _connectivityLabel(reading.connectivity),
              detail: reading.connectivity == ConnectivityStatus.online
                  ? 'Streaming'
                  : 'Check coverage',
              status: switch (reading.connectivity) {
                ConnectivityStatus.online => SafetyStatus.normal,
                ConnectivityStatus.degraded ||
                ConnectivityStatus.offlineBuffering => SafetyStatus.warning,
                ConnectivityStatus.offline => SafetyStatus.offline,
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionHeader(title: 'Motion'),
        _motionCard(
          reading,
          viewModel.hasActiveAlert(helmetId, AlertType.fall),
        ),
        const SizedBox(height: AppSpacing.lg),
        LiveSensorDiagnostics(
          reading: reading,
          assessment: assessment,
          isLive: !notLive,
        ),
      ],
    );
  }

  Widget _motionCard(SensorReading reading, bool activeFallAlert) {
    final fallStatus = activeFallAlert
        ? SafetyStatus.critical
        : SafetyStatus.normal;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'IMU / MOTION',
                  style: AppTypography.overline.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                _fallStatusLabel(reading.fallStatus),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _axis(reading.accelXG, 'Accel X')),
              Expanded(child: _axis(reading.accelYG, 'Accel Y')),
              Expanded(child: _axis(reading.accelZG, 'Accel Z')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _rotation(reading.gyroXDegreesPerSecond, 'Gyro X'),
              ),
              Expanded(
                child: _rotation(reading.gyroYDegreesPerSecond, 'Gyro Y'),
              ),
              Expanded(
                child: _rotation(reading.gyroZDegreesPerSecond, 'Gyro Z'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(
                status: fallStatus,
                label: activeFallAlert
                    ? 'Confirmed fall alert'
                    : 'No active fall alert',
              ),
              Text(
                'Rule-based',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _axis(double? value, String label) => _AxisValue(
    value: formatMeasurement(value, SensorUnit.standardGravity),
    label: label,
  );

  Widget _rotation(double? value, String label) => _AxisValue(
    value: value == null ? 'Unavailable' : '${formatNumber(value)} °/s',
    label: label,
  );

  String _gpsValue(SensorReading reading) => switch (reading.gpsStatus) {
    GpsStatus.valid when reading.location != null => 'Valid',
    GpsStatus.acquiring => 'Acquiring',
    GpsStatus.lost => 'Lost',
    GpsStatus.invalid || GpsStatus.valid => 'Unavailable',
  };

  String _gpsStatus(SensorReading reading) => switch (reading.gpsStatus) {
    GpsStatus.valid when reading.location != null =>
      reading.location!.isLastKnown ? 'Last known' : 'Current fix',
    GpsStatus.acquiring => 'Acquiring',
    GpsStatus.lost when reading.location?.isLastKnown == true => 'Last known',
    GpsStatus.lost => 'GPS lost',
    GpsStatus.invalid || GpsStatus.valid => 'No valid fix',
  };

  SafetyStatus _gpsSafetyStatus(SensorReading reading) =>
      switch (reading.gpsStatus) {
        GpsStatus.valid when reading.location != null =>
          reading.location!.isLastKnown
              ? SafetyStatus.stale
              : SafetyStatus.normal,
        GpsStatus.acquiring => SafetyStatus.pending,
        GpsStatus.lost => SafetyStatus.offline,
        GpsStatus.invalid || GpsStatus.valid => SafetyStatus.unknown,
      };

  String _connectivityLabel(ConnectivityStatus status) => switch (status) {
    ConnectivityStatus.online => 'Online',
    ConnectivityStatus.degraded => 'Degraded',
    ConnectivityStatus.offlineBuffering => 'Buffering offline',
    ConnectivityStatus.offline => 'Offline',
  };

  String _fallStatusLabel(FallStatus status) => switch (status) {
    FallStatus.notEvaluated => 'Detector idle',
    FallStatus.normal => 'Normal motion',
    FallStatus.freeFallCandidate => 'Free-fall candidate',
    FallStatus.impactDetected => 'Impact detected',
    FallStatus.stillnessCandidate => 'Stillness check',
    FallStatus.confirmed => 'Fall confirmed',
    FallStatus.cooldown => 'Cooldown',
  };

  String _stateLabel(MonitoringState state) => switch (state) {
    MonitoringState.loading => 'Loading',
    MonitoringState.empty => 'No Data',
    MonitoringState.safe => 'Safe',
    MonitoringState.warning => 'Warning',
    MonitoringState.critical => 'Critical',
    MonitoringState.stale => 'Stale • Last known values',
    MonitoringState.offline => 'Offline',
    MonitoringState.sensorFault => 'Sensor Fault',
    MonitoringState.warmingUp => 'Gas sensor warming up',
    MonitoringState.permissionDenied => 'Permission Denied',
    MonitoringState.backendError => 'Backend Error',
  };
}

/// Card for non-numeric readings (GPS fix, link state).
class _TextReadingCard extends StatelessWidget {
  const _TextReadingCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.detail,
    required this.status,
  });

  final String label;
  final IconData icon;
  final String value;
  final String detail;
  final SafetyStatus status;

  @override
  Widget build(BuildContext context) => AppCard(
    status: status.needsAttention ? status : null,
    semanticLabel: '$label, $value, $detail',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: AppSizes.iconMd, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          value,
          style: AppTypography.metric.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        StatusChip(status: status, label: detail),
      ],
    ),
  );
}

class _AxisValue extends StatelessWidget {
  const _AxisValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: AppTypography.bodyStrong.copyWith(
            color: AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      Text(
        label,
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}
