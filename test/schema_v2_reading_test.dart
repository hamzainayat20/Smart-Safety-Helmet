import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/firebase_realtime_repositories.dart';
import 'package:smart_safety/data/sensor_reading_ingestion.dart';
import 'package:smart_safety/domain/models.dart';

/// A record exactly as the AWS ingestion Lambda stores it at
/// helmets/{helmetId}/current: the firmware's schema 2.0 payload plus the
/// three backend-owned fields.
Map<String, Object?> physicalRecord({
  String eventId = 'helmet001_1a2b3c4d_7',
  int deviceTimestamp = 1794927600123,
  Map<String, Object?> overrides = const {},
  List<String> remove = const [],
}) {
  final record = <String, Object?>{
    'schemaVersion': '2.0',
    'eventId': eventId,
    'helmetId': 'helmet001',
    'deviceTimestamp': deviceTimestamp,
    'firmwareVersion': '0.3.0-staging',
    'temperatureC': 29.4,
    'humidityPct': 61.2,
    'heatIndexC': 31.8,
    'accelXG': 0.04,
    'accelYG': -0.002,
    'accelZG': 1.094,
    'gyroXDegreesPerSecond': 0.012,
    'gyroYDegreesPerSecond': -0.02,
    'gyroZDegreesPerSecond': 0.005,
    'mq7Raw': 208,
    'mq7WarmUp': true,
    'mq135WarmUp': false,
    // RTDB delivers nested objects as untyped maps.
    'fallFeatures': <Object?, Object?>{
      'acc_mean': 1.0948,
      'acc_std': 0.0021,
      'acc_min': 1.0901,
      'acc_max': 1.0995,
      'gyro_mean': 0.21,
      'gyro_std': 0.08,
      'gyro_max': 0.45,
      'jerk_mean': 0.11,
      'jerk_max': 0.35,
    },
    'samplingRateHz': 50,
    'windowSamples': 100,
    'windowEndTimestamp': deviceTimestamp - 200,
    'sensorFaults': <Object?>[
      'batteryUnavailable',
      'gpsUnavailable',
      'mq135HeaterStateUnknown',
      'mq135ReadFailed',
      'mq135Uncalibrated',
      'mq7HeaterStateUnknown',
      'mq7Uncalibrated',
    ],
    'serverReceivedAt': deviceTimestamp + 150,
    'connectivity': 'online',
    'severity': 'unassessed',
    ...overrides,
  };
  for (final key in remove) {
    record.remove(key);
  }
  return record;
}

void main() {
  group('schema 2.0 current records', () {
    test('a full physical record keeps every genuine field', () {
      final reading = parseCurrentReadingRecord(physicalRecord(), 'helmet001')!;

      expect(reading.schemaVersion, '2.0');
      expect(reading.eventId, 'helmet001_1a2b3c4d_7');
      expect(reading.helmetId, 'helmet001');
      expect(reading.firmwareVersion, '0.3.0-staging');
      expect(reading.deviceTimestamp.millisecondsSinceEpoch, 1794927600123);
      expect(reading.serverReceivedAt.millisecondsSinceEpoch, 1794927600273);
      expect(reading.connectivity, ConnectivityStatus.online);
      expect(reading.temperatureC, 29.4);
      expect(reading.humidityPct, 61.2);
      expect(reading.heatIndexC, 31.8);
      expect(reading.accelXG, 0.04);
      expect(reading.accelYG, -0.002);
      expect(reading.accelZG, 1.094);
      expect(reading.gyroXDegreesPerSecond, 0.012);
      expect(reading.gyroYDegreesPerSecond, -0.02);
      expect(reading.gyroZDegreesPerSecond, 0.005);
      expect(reading.mq7Raw, 208);
      expect(reading.mq7WarmUp, isTrue);
      expect(reading.mq135Raw, isNull);
      expect(reading.mq135WarmUp, isFalse);

      final window = reading.fallWindow!;
      expect(window.features, {
        'acc_mean': 1.0948,
        'acc_std': 0.0021,
        'acc_min': 1.0901,
        'acc_max': 1.0995,
        'gyro_mean': 0.21,
        'gyro_std': 0.08,
        'gyro_max': 0.45,
        'jerk_mean': 0.11,
        'jerk_max': 0.35,
      });
      expect(window.features.keys.toList(), FallWindowFeatures.featureKeys);
      expect(window.samplingRateHz, 50);
      expect(window.windowSamples, 100);
      expect(window.windowEndTimestamp.millisecondsSinceEpoch, 1794927599923);

      expect(reading.sensorFaults, containsAll(<SensorFault>[
        SensorFault.mq135ReadFailed,
        SensorFault.mq135Uncalibrated,
        SensorFault.mq135HeaterStateUnknown,
        SensorFault.mq7Uncalibrated,
        SensorFault.mq7HeaterStateUnknown,
        SensorFault.gpsUnavailable,
        SensorFault.batteryUnavailable,
      ]));
      // Raw MQ-7 is never reinterpreted as legacy or calibrated gas.
      expect(reading.gasRaw, isNull);
      expect(reading.gasPpm, isNull);
    });

    test('every backend fault name parses (none can break the live stream)', () {
      const contractFaults = [
        'mpuReadFailed',
        'dhtReadFailed',
        'mq7ReadFailed',
        'mq7Uncalibrated',
        'mq7HeaterStateUnknown',
        'mq135ReadFailed',
        'mq135Uncalibrated',
        'mq135HeaterStateUnknown',
        'fallWindowUnavailable',
        'gpsUnavailable',
        'batteryUnavailable',
      ];
      final reading = parseCurrentReadingRecord(
        physicalRecord(
          overrides: {'sensorFaults': contractFaults},
          remove: const [
            'temperatureC', 'humidityPct', 'heatIndexC', 'accelXG', 'accelYG',
            'accelZG', 'gyroXDegreesPerSecond', 'gyroYDegreesPerSecond',
            'gyroZDegreesPerSecond', 'mq7Raw', 'fallFeatures',
            'samplingRateHz', 'windowSamples', 'windowEndTimestamp',
          ],
        ),
        'helmet001',
      )!;
      expect(reading.sensorFaults.toSet(), SensorFault.values.toSet());
    });

    test('a partial record parses with absent values, never zeros', () {
      final reading = parseCurrentReadingRecord(
        physicalRecord(
          overrides: {
            'sensorFaults': [
              'batteryUnavailable',
              'dhtReadFailed',
              'fallWindowUnavailable',
              'gpsUnavailable',
              'mq135ReadFailed',
              'mq7ReadFailed',
              'mq7Uncalibrated',
            ],
          },
          remove: const [
            'temperatureC', 'humidityPct', 'heatIndexC', 'mq7Raw',
            'fallFeatures', 'samplingRateHz', 'windowSamples',
            'windowEndTimestamp',
          ],
        ),
        'helmet001',
      )!;
      expect(reading.temperatureC, isNull);
      expect(reading.humidityPct, isNull);
      expect(reading.heatIndexC, isNull);
      expect(reading.mq7Raw, isNull);
      expect(reading.fallWindow, isNull);
      expect(reading.accelZG, 1.094);
      expect(
        reading.sensorFaults,
        containsAll([
          SensorFault.dhtReadFailed,
          SensorFault.mq7ReadFailed,
          SensorFault.fallWindowUnavailable,
        ]),
      );
    });

    test('an incomplete or malformed window is unavailable, not partial', () {
      final missingFeature = physicalRecord();
      (missingFeature['fallFeatures']! as Map).remove('jerk_max');
      final missingTimestamp = physicalRecord(remove: const ['windowEndTimestamp']);
      final negative = physicalRecord();
      (negative['fallFeatures']! as Map)['acc_std'] = -1;
      for (final record in [missingFeature, missingTimestamp, negative]) {
        final reading = parseCurrentReadingRecord(record, 'helmet001')!;
        expect(reading.fallWindow, isNull);
        expect(reading.temperatureC, 29.4, reason: 'rest of reading kept');
      }
    });

    test('schema 2.0 keeps the existing calibrated-gas monitoring semantics', () {
      for (final warmUp in [true, false]) {
        final reading = parseCurrentReadingRecord(
          physicalRecord(overrides: {'mq7WarmUp': warmUp}),
          'helmet001',
        )!;
        expect(reading.gasWarmUp, isTrue);
        expect(reading.mq7WarmUp, warmUp);
      }
    });

    test('schema 2.0 round-trips through toJson without losing fields', () {
      final reading = parseCurrentReadingRecord(physicalRecord(), 'helmet001')!;
      final json = reading.toJson();
      expect(json['mq7Raw'], 208);
      expect(json['mq7WarmUp'], isTrue);
      expect(json['mq135WarmUp'], isFalse);
      expect(json['samplingRateHz'], 50);
      expect(json['windowSamples'], 100);
      expect(json['windowEndTimestamp'], 1794927599923);
      expect((json['fallFeatures'] as Map)['jerk_max'], 0.35);
      final again = SensorReading.fromJson(json);
      expect(again.fallWindow!.features, reading.fallWindow!.features);
    });

    test('an empty current node is no reading', () {
      expect(parseCurrentReadingRecord(null, 'helmet001'), isNull);
    });
  });

  group('legacy records stay compatible', () {
    test('schema 1.0 backend record parses as before', () {
      final reading = parseCurrentReadingRecord({
        'schemaVersion': '1.0',
        'eventId': 'helmet001_test_1',
        'helmetId': 'helmet001',
        'deviceTimestamp': 1775900000000,
        'firmwareVersion': '0.2.0-staging',
        'temperatureC': 25,
        'humidityPct': 50,
        'heatIndexC': 25.5,
        'accelXG': 0,
        'accelYG': 0,
        'accelZG': 1,
        'gasWarmUp': true,
        'fallStatus': 'notEvaluated',
        'sensorFaults': [
          'mq7ReadFailed',
          'mq7Uncalibrated',
          'mq7HeaterStateUnknown',
          'gpsUnavailable',
          'batteryUnavailable',
        ],
        'serverReceivedAt': 1775900000100,
        'connectivity': 'online',
        'severity': 'unassessed',
      }, 'helmet001')!;
      expect(reading.schemaVersion, '1.0');
      expect(reading.temperatureC, 25);
      expect(reading.gasWarmUp, isTrue);
      expect(reading.mq7Raw, isNull);
      expect(reading.mq7WarmUp, isNull);
      expect(reading.fallWindow, isNull);
    });

    test('manual-sketch mq7Raw outside schema 2.0 still maps to gasRaw', () {
      final normalized = normalizeSensorReadingAtIngestion({
        'schemaVersion': '1.0',
        'mq7Raw': 300,
      });
      expect(normalized['gasRaw'], 300);
      expect(normalized.containsKey('mq7Raw'), isFalse);
      expect(normalized['gasWarmUp'], isTrue);
    });

    test('schema 2.0 mq7Raw is never folded into legacy gasRaw', () {
      final normalized = normalizeSensorReadingAtIngestion({
        'schemaVersion': '2.0',
        'mq7Raw': 300,
      });
      expect(normalized['mq7Raw'], 300);
      expect(normalized.containsKey('gasRaw'), isFalse);
    });
  });
}
