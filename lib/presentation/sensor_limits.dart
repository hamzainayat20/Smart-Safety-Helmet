import 'package:flutter/widgets.dart';

import '../application/dashboard_view_model.dart';
import '../domain/models.dart';
import 'design_system/safety_status.dart';

/// Warning/critical limits used to colour individual sensor readings.
///
/// Prefer [SensorLimits.fromConfiguration] (the helmet's live configuration
/// from Firebase). [SensorLimits.defaults] mirrors FYP Table 3.2 and is only
/// used — and labelled as such — when the configuration cannot be read.
@immutable
final class SensorLimits {
  const SensorLimits({
    required this.temperatureWarningC,
    required this.temperatureCriticalC,
    required this.humidityWarningLowPct,
    required this.humidityCriticalLowPct,
    required this.humidityWarningHighPct,
    required this.humidityCriticalHighPct,
    required this.gasWarningPpm,
    required this.gasCriticalPpm,
    required this.isConfigured,
  });

  factory SensorLimits.fromConfiguration(HelmetConfiguration configuration) =>
      SensorLimits(
        temperatureWarningC: configuration.temperatureWarningC,
        temperatureCriticalC: configuration.temperatureCriticalC,
        humidityWarningLowPct: configuration.humidityWarningLowPct,
        humidityCriticalLowPct: configuration.humidityCriticalLowPct,
        humidityWarningHighPct: configuration.humidityWarningHighPct,
        humidityCriticalHighPct: configuration.humidityCriticalHighPct,
        gasWarningPpm: configuration.gasWarningPpm,
        gasCriticalPpm: configuration.gasCriticalPpm,
        isConfigured: true,
      );

  /// FYP Table 3.2 environmental hazard thresholds.
  static const defaults = SensorLimits(
    temperatureWarningC: 40,
    temperatureCriticalC: 50,
    humidityWarningLowPct: 30,
    humidityCriticalLowPct: 20,
    humidityWarningHighPct: 80,
    humidityCriticalHighPct: 90,
    gasWarningPpm: 100,
    gasCriticalPpm: 200,
    isConfigured: false,
  );

  /// Battery levels are not part of the helmet configuration; Table 3.2.
  static const int batteryWarningPct = 30;
  static const int batteryCriticalPct = 20;

  final double temperatureWarningC;
  final double temperatureCriticalC;
  final double humidityWarningLowPct;
  final double humidityCriticalLowPct;
  final double humidityWarningHighPct;
  final double humidityCriticalHighPct;
  final double gasWarningPpm;
  final double gasCriticalPpm;

  /// Whether these limits came from the helmet's live configuration.
  final bool isConfigured;

  String get sourceLabel =>
      isConfigured ? 'Configured limits' : 'Default limits (Table 3.2)';

  SafetyStatus temperature(double? celsius) =>
      _upper(celsius, temperatureWarningC, temperatureCriticalC);

  SafetyStatus gas(double? ppm, {bool warmingUp = false}) =>
      warmingUp ? SafetyStatus.pending : _upper(ppm, gasWarningPpm, gasCriticalPpm);

  SafetyStatus humidity(double? percent) {
    if (percent == null) return SafetyStatus.unknown;
    if (percent < humidityCriticalLowPct || percent > humidityCriticalHighPct) {
      return SafetyStatus.critical;
    }
    if (percent < humidityWarningLowPct || percent > humidityWarningHighPct) {
      return SafetyStatus.warning;
    }
    return SafetyStatus.normal;
  }

  static SafetyStatus battery(int? percent) {
    if (percent == null) return SafetyStatus.unknown;
    if (percent < batteryCriticalPct) return SafetyStatus.critical;
    if (percent <= batteryWarningPct) return SafetyStatus.warning;
    return SafetyStatus.normal;
  }

  static SafetyStatus _upper(double? value, double warning, double critical) {
    if (value == null) return SafetyStatus.unknown;
    if (value > critical) return SafetyStatus.critical;
    if (value >= warning) return SafetyStatus.warning;
    return SafetyStatus.normal;
  }
}

/// Plain-language reading status for a sensor tile.
String readingStatusLabel(SafetyStatus status) => switch (status) {
  SafetyStatus.normal => 'Normal',
  SafetyStatus.warning => 'Elevated',
  SafetyStatus.critical => 'Dangerous',
  SafetyStatus.pending => 'Sensor warming up',
  SafetyStatus.stale => 'Last known value',
  SafetyStatus.offline => 'Connection lost',
  SafetyStatus.unknown => 'No reading',
};

/// Streams the helmet's configured limits from the existing
/// `ConfigurationRepository` (read-only) and rebuilds with them.
///
/// Falls back to [SensorLimits.defaults] — labelled via
/// [SensorLimits.sourceLabel] — while loading, if no configuration exists, or
/// if the read is not permitted.
class HelmetLimitsBuilder extends StatefulWidget {
  const HelmetLimitsBuilder({
    super.key,
    required this.viewModel,
    required this.helmetId,
    required this.builder,
  });

  final DashboardViewModel viewModel;
  final String? helmetId;
  final Widget Function(BuildContext context, SensorLimits limits) builder;

  @override
  State<HelmetLimitsBuilder> createState() => _HelmetLimitsBuilderState();
}

class _HelmetLimitsBuilderState extends State<HelmetLimitsBuilder> {
  Stream<HelmetConfiguration?>? _configuration;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant HelmetLimitsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.helmetId != widget.helmetId ||
        oldWidget.viewModel != widget.viewModel) {
      _subscribe();
    }
  }

  void _subscribe() {
    final helmetId = widget.helmetId;
    _configuration = helmetId == null
        ? null
        : widget.viewModel.dependencies.configuration.watchConfiguration(
            widget.viewModel.profile,
            helmetId,
          );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _configuration;
    if (stream == null) return widget.builder(context, SensorLimits.defaults);
    return StreamBuilder<HelmetConfiguration?>(
      stream: stream,
      builder: (context, snapshot) {
        final configuration = snapshot.hasError ? null : snapshot.data;
        return widget.builder(
          context,
          configuration == null
              ? SensorLimits.defaults
              : SensorLimits.fromConfiguration(configuration),
        );
      },
    );
  }
}
