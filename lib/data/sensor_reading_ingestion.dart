import '../domain/models.dart';

/// Normalizes the verified manual-sketch JSON at the data boundary.
///
/// Legacy names are deliberately kept out of [SensorReading]. This adapter is
/// read-only preparation for future trusted ingestion; it does not write data
/// or authorize a device.
Map<String, dynamic> normalizeSensorReadingAtIngestion(
  Map<String, dynamic> source,
) {
  final result = Map<String, dynamic>.from(source);
  // Telemetry schema 2.0 names MQ-7 explicitly (mq7Raw / mq7WarmUp) and has no
  // calibrated-gas fields. Its names are canonical and must not be folded into
  // the legacy manual-sketch gas fields.
  final isSchemaV2 = result['schemaVersion'] == '2.0';

  void alias(String legacy, String canonical) {
    if (!result.containsKey(canonical) && result.containsKey(legacy)) {
      result[canonical] = result[legacy];
    }
    result.remove(legacy);
  }

  alias('temperature', 'temperatureC');
  alias('humidity', 'humidityPct');
  alias('heatIndex', 'heatIndexC');
  alias('accelX', 'accelXG');
  alias('accelY', 'accelYG');
  alias('accelZ', 'accelZG');
  alias('gyroX', 'gyroXDegreesPerSecond');
  alias('gyroY', 'gyroYDegreesPerSecond');
  alias('gyroZ', 'gyroZDegreesPerSecond');
  if (!isSchemaV2) alias('mq7Raw', 'gasRaw');
  alias('mq7AdcVoltage', 'gasAdcVoltage');
  alias('mq7Voltage', 'gasSensorVoltage');

  final rawDigital = result.remove('mq7Digital');
  if (!result.containsKey('gasDigitalThreshold') && rawDigital != null) {
    result['gasDigitalThreshold'] = switch (rawDigital) {
      0 => true,
      1 => false,
      _ => throw ModelValidationException(
        'mq7Digital must be the verified active-low level 0 or 1',
        source,
      ),
    };
  }

  final faults = <String>{
    ...?switch (result['sensorFaults']) {
      final List values => values.whereType<String>(),
      null => null,
      _ => throw ModelValidationException(
        'sensorFaults must be a list',
        source,
      ),
    },
  };
  if (result.remove('mpuValid') == false) faults.add('mpuReadFailed');
  if (result.remove('dhtValid') == false) faults.add('dhtReadFailed');
  if (result.remove('mq7Valid') == false) faults.add('mq7ReadFailed');

  final hasMq7Diagnostics =
      result.containsKey('gasRaw') ||
      result.containsKey('gasAdcVoltage') ||
      result.containsKey('gasSensorVoltage') ||
      result.containsKey('gasDigitalThreshold');
  if (hasMq7Diagnostics) {
    result['gasPpm'] = null;
    result['gasWarmUp'] = true;
    faults
      ..add('mq7Uncalibrated')
      ..add('mq7HeaterStateUnknown');
  }

  if (isSchemaV2) {
    // Schema 2.0 never carries calibrated gas ppm, so the legacy calibrated-gas
    // channel is reported as not ready, exactly as it was for schema 2.0
    // records before this adapter preserved mq7Raw separately. The device's
    // own mq7WarmUp flag is kept unchanged on the reading for display.
    result.remove('gasPpm');
    result['gasWarmUp'] = true;
  }

  if (!result.containsKey('location')) faults.add('gpsUnavailable');
  if (!result.containsKey('batteryPct')) faults.add('batteryUnavailable');

  result['fallStatus'] ??= FallStatus.notEvaluated.name;
  result['severity'] ??= SafetySeverity.unassessed.name;
  result['gpsStatus'] ??= GpsStatus.invalid.name;
  if (faults.isNotEmpty) result['sensorFaults'] = faults.toList()..sort();
  return result;
}
