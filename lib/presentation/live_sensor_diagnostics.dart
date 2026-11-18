import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/mq7_co_estimate.dart';
import 'design_system/design_system.dart';
import 'formatters.dart';

/// Shown wherever a value is absent. Never replaced by zero or a guess.
const String unavailableLabel = 'Unavailable';

/// Plain-language description of a device-reported sensor fault.
String sensorFaultLabel(SensorFault fault) => switch (fault) {
  SensorFault.mpuReadFailed => 'Motion sensor read failed',
  SensorFault.dhtReadFailed => 'Temperature/humidity sensor (DHT22) not reading',
  SensorFault.mq7ReadFailed => 'Gas sensor (MQ-7) not reading',
  SensorFault.mq7Uncalibrated => 'Gas sensor (MQ-7) not calibrated',
  SensorFault.mq7HeaterStateUnknown => 'Gas sensor (MQ-7) heater state unknown',
  SensorFault.mq135ReadFailed => 'Air-quality sensor (MQ-135) not fitted',
  SensorFault.mq135Uncalibrated => 'Air-quality sensor (MQ-135) not calibrated',
  SensorFault.mq135HeaterStateUnknown =>
    'Air-quality sensor (MQ-135) heater state unknown',
  SensorFault.fallWindowUnavailable => 'Fall-model window not ready',
  SensorFault.gpsUnavailable => 'GPS not fitted',
  SensorFault.batteryUnavailable => 'Battery monitor not fitted',
};

/// "Live sensor diagnostics": every genuine telemetry field of the current
/// reading, grouped for readability. It deliberately sits below the primary
/// safety information and keeps raw model features collapsed.
class LiveSensorDiagnostics extends StatelessWidget {
  const LiveSensorDiagnostics({
    super.key,
    required this.reading,
    this.assessment,
    this.isLive = true,
    this.nowUtc,
    this.mq7CleanAirRaw,
  });

  final SensorReading reading;

  /// AI assessment for this exact reading, if one has been produced.
  final SafetyAssessment? assessment;

  /// False when the reading is stale or the helmet is offline.
  final bool isLive;

  /// Clock override for deterministic tests.
  final DateTime? nowUtc;

  /// Clean-air MQ-7 baseline for the display-only CO estimate. Null uses the
  /// SMART_SAFETY_MQ7_CLEAN_AIR_RAW build define (unset = no estimate).
  final int? mq7CleanAirRaw;

  @override
  Widget build(BuildContext context) {
    final updated = formatRelativeTime(reading.serverReceivedAt, nowUtc: nowUtc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Live sensor diagnostics',
          subtitle: isLive
              ? 'Last updated $updated'
              : 'Stale · last updated $updated',
        ),
        ResponsiveTileGrid(
          minTileWidth: 300,
          maxColumns: 2,
          children: [
            _environment(),
            _motion(),
            _fallWindow(context),
            _gas(),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _deviceHealth(updated),
      ],
    );
  }

  Widget _environment() => _GroupCard(
    title: 'Environment',
    icon: Icons.thermostat_rounded,
    children: [
      KeyValueRow(
        label: 'Temperature',
        value: formatMeasurement(reading.temperatureC, SensorUnit.degreesCelsius),
      ),
      KeyValueRow(
        label: 'Humidity',
        value: formatMeasurement(
          reading.humidityPct,
          SensorUnit.percentRelativeHumidity,
        ),
      ),
      KeyValueRow(
        label: 'Heat index',
        value: formatMeasurement(reading.heatIndexC, SensorUnit.degreesCelsius),
      ),
    ],
  );

  Widget _motion() => _GroupCard(
    title: 'Motion (instantaneous)',
    icon: Icons.screen_rotation_alt_rounded,
    children: [
      KeyValueRow(label: 'Accel X', value: _g(reading.accelXG)),
      KeyValueRow(label: 'Accel Y', value: _g(reading.accelYG)),
      KeyValueRow(label: 'Accel Z', value: _g(reading.accelZG)),
      KeyValueRow(label: 'Gyro X', value: _dps(reading.gyroXDegreesPerSecond)),
      KeyValueRow(label: 'Gyro Y', value: _dps(reading.gyroYDegreesPerSecond)),
      KeyValueRow(label: 'Gyro Z', value: _dps(reading.gyroZDegreesPerSecond)),
    ],
  );

  Widget _fallWindow(BuildContext context) {
    final window = reading.fallWindow;
    final fall = assessment?.fall;
    final fallProbability = fall?.status == InferenceStatus.completed
        ? fall?.probability
        : null;
    final fallThreshold = fall?.threshold;
    return _GroupCard(
      title: 'Fall-model window',
      icon: Icons.analytics_outlined,
      children: [
        KeyValueRow(
          label: 'AI fall check',
          value: fallProbability == null
              ? unavailableLabel
              : '${_percent(fallProbability)} fall probability'
                    '${fallThreshold == null ? '' : ' (alert at ${_percent(fallThreshold)})'}',
        ),
        KeyValueRow(
          label: 'Window',
          value: window == null
              ? unavailableLabel
              : '${window.windowSamples} samples at ${window.samplingRateHz} Hz',
        ),
        KeyValueRow(
          label: 'Window ended',
          value: window == null
              ? unavailableLabel
              : formatUtcTimestamp(window.windowEndTimestamp),
        ),
        if (window != null)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const ValueKey('advanced-fall-features'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              expansionAnimationStyle: AnimationStyle(
                duration: AppMotion.of(context, AppMotion.standard),
                reverseDuration: AppMotion.of(context, AppMotion.standard),
              ),
              title: Text(
                'Advanced fall-model features',
                style: AppTypography.label,
              ),
              subtitle: Text(
                'Raw model inputs, for diagnostics only',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              children: [
                for (final entry in window.features.entries)
                  KeyValueRow(
                    label: entry.key,
                    value:
                        '${_featureNumber(entry.value)} ${_featureUnit(entry.key)}',
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _gas() {
    final gas = assessment?.gas;
    // Only a class the backend genuinely produced is shown.
    final producedGas =
        gas != null &&
            gas.status == InferenceStatus.completed &&
            gas.gasClass != GasClass.unknown
        ? gas
        : null;
    return _GroupCard(
      title: 'Gas',
      icon: Icons.air_rounded,
      children: [
        KeyValueRow(
          label: 'MQ-7',
          value: reading.mq7Raw == null
              ? unavailableLabel
              : '${reading.mq7Raw} (Raw ADC — not ppm)',
        ),
        KeyValueRow(
          label: 'Estimated CO (uncalibrated)',
          value: reading.mq7Raw == null
              ? unavailableLabel
              : estimateMq7Co(
                  raw: reading.mq7Raw,
                  cleanAirRaw:
                      mq7CleanAirRaw ??
                      parseMq7CleanAirRaw(mq7CleanAirRawDefine),
                ).label,
        ),
        KeyValueRow(
          label: 'MQ-7 readiness',
          value: switch (reading.mq7WarmUp) {
            null => unavailableLabel,
            true => 'Warming up / not ready',
            false => 'Reported ready',
          },
        ),
        KeyValueRow(
          label: 'MQ-135',
          value: reading.mq135Raw == null
              ? unavailableLabel
              : '${reading.mq135Raw} (Raw ADC — not ppm)',
        ),
        KeyValueRow(
          label: 'AI gas class',
          value: producedGas == null
              ? unavailableLabel
              : _gasSummary(producedGas),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            'Raw ADC counts are uncalibrated. They do not show whether carbon '
            'monoxide levels are safe or dangerous. The estimated CO value is '
            'a rough datasheet approximation (errors of 2x or more), is not '
            'a measurement, and is never used for safety status or alerts.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceHealth(String updated) {
    final faults = reading.sensorFaults;
    return _GroupCard(
      title: 'Device health',
      icon: Icons.memory_rounded,
      children: [
        KeyValueRow(label: 'Helmet', value: reading.helmetId),
        KeyValueRow(
          label: 'Link',
          value: isLive
              ? '${_connectivityLabel(reading.connectivity)} · updated $updated'
              : 'Stale · last updated $updated',
        ),
        KeyValueRow(
          label: 'Device clock',
          value: formatUtcTimestamp(reading.deviceTimestamp),
        ),
        KeyValueRow(
          label: 'Server received',
          value: formatUtcTimestamp(reading.serverReceivedAt),
        ),
        KeyValueRow(label: 'Firmware', value: reading.firmwareVersion),
        KeyValueRow(label: 'Schema', value: reading.schemaVersion),
        KeyValueRow(label: 'Event ID', value: reading.eventId),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Sensor status',
          style: AppTypography.label.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (faults.isEmpty)
          const StatusChip(
            status: SafetyStatus.normal,
            label: 'No sensor faults reported',
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final fault in faults)
                StatusChip(
                  status: _faultSeverity(fault),
                  label: sensorFaultLabel(fault),
                ),
            ],
          ),
      ],
    );
  }

  static String _g(double? value) => value == null
      ? unavailableLabel
      : '${formatNumber(value, fractionDigits: 3)} ${SensorUnit.standardGravity.symbol}';

  static String _dps(double? value) => value == null
      ? unavailableLabel
      : '${formatNumber(value, fractionDigits: 2)} °/s';

  /// Up to four decimals without padding zeros (0.35, 1.0995, 50).
  static String _featureNumber(double value) {
    final fixed = value.toStringAsFixed(4);
    final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  static String _percent(double fraction) =>
      '${formatNumber(fraction * 100, fractionDigits: 1)}%';

  static String _featureUnit(String key) => key.startsWith('acc_')
      ? 'g'
      : key.startsWith('gyro_')
      ? '°/s'
      : 'g/s';

  static String _gasSummary(GasPrediction gas) {
    final confidence = gas.confidence;
    return '${_gasClassLabel(gas.gasClass)}'
        '${confidence == null ? '' : ' (${_percent(confidence)} confidence)'}'
        '${gas.outOfDistribution ? ' · outside training range' : ''}';
  }

  static String _gasClassLabel(GasClass value) => switch (value) {
    GasClass.mixture => 'Mixture',
    GasClass.noGas => 'No gas',
    GasClass.perfume => 'Perfume',
    GasClass.smoke => 'Smoke',
    GasClass.unknown => unavailableLabel,
  };

  static String _connectivityLabel(ConnectivityStatus status) =>
      switch (status) {
        ConnectivityStatus.online => 'Online',
        ConnectivityStatus.degraded => 'Degraded',
        ConnectivityStatus.offlineBuffering => 'Buffering offline',
        ConnectivityStatus.offline => 'Offline',
      };

  /// Read failures of fitted sensors are warnings; hardware that is simply
  /// not fitted, or a window still filling, is informational.
  static SafetyStatus _faultSeverity(SensorFault fault) => switch (fault) {
    SensorFault.mpuReadFailed ||
    SensorFault.dhtReadFailed ||
    SensorFault.mq7ReadFailed => SafetyStatus.warning,
    _ => SafetyStatus.unknown,
  };
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: AppTypography.overline.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    ),
  );
}
