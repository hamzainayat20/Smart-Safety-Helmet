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
  alias('mq7Raw', 'gasRaw');
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

  if (!result.containsKey('location')) faults.add('gpsUnavailable');
  if (!result.containsKey('batteryPct')) faults.add('batteryUnavailable');

  result['fallStatus'] ??= FallStatus.notEvaluated.name;
  result['severity'] ??= SafetySeverity.unassessed.name;
  result['gpsStatus'] ??= GpsStatus.invalid.name;
  if (faults.isNotEmpty) result['sensorFaults'] = faults.toList()..sort();
  return result;
}
