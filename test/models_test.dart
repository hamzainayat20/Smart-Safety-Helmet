import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/sensor_reading_ingestion.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/user_role.dart';

void main() {
  group('typed model parsing and validation', () {
    test('legacy user profile parses without allowing unknown role values', () {
      final profile = UserProfile.fromJson({
        'schemaVersion': '1.0',
        'uid': 'worker-1',
        'name': 'Demo Worker',
        'email': 'worker@example.test',
        'organization': 'Main Site',
        'role': 1,
        'active': true,
        'updatedAt': 1000,
      });

      expect(profile.role, UserRole.worker);
      expect(profile.organizationName, 'Main Site');
      expect(
        () => UserProfile.fromJson({...profile.toJson(), 'role': 'owner'}),
        throwsA(isA<ModelValidationException>()),
      );
    });

    test(
      'unknown sensor measurements remain null and are omitted from JSON',
      () {
        final reading = SensorReading.fromJson({
          'schemaVersion': '1.0',
          'eventId': 'event-1',
          'helmetId': 'H-01',
          'deviceTimestamp': 1000,
          'serverReceivedAt': 1100,
          'gasWarmUp': false,
          'gpsStatus': 'acquiring',
          'connectivity': 'online',
          'firmwareVersion': '1.0.0',
          'severity': 'safe',
        });

        expect(reading.temperatureC, isNull);
        expect(reading.batteryPct, isNull);
        expect(reading.heatIndexC, isNull);
        expect(reading.gasRaw, isNull);
        expect(reading.fallStatus, FallStatus.notEvaluated);
        expect(reading.sensorFaults, isEmpty);
        expect(reading.severity, SafetySeverity.safe);
        expect(reading.toJson(), isNot(contains('temperatureC')));
        expect(reading.toJson(), isNot(contains('batteryPct')));
        expect(reading.toJson(), isNot(contains('gasRaw')));
      },
    );

    test('missing assessment defaults to typed unassessed, never safe', () {
      final reading = SensorReading.fromJson({
        'schemaVersion': '1.0',
        'eventId': 'event-unassessed',
        'helmetId': 'H-01',
        'deviceTimestamp': 1000,
        'serverReceivedAt': 1100,
        'gasWarmUp': true,
        'gpsStatus': 'invalid',
        'connectivity': 'online',
        'firmwareVersion': 'manual-test',
      });

      expect(reading.severity, SafetySeverity.unassessed);
      expect(reading.severity, isNot(SafetySeverity.safe));
      expect(reading.fallStatus, FallStatus.notEvaluated);
      expect(reading.gasPpm, isNull);
    });

    test('extended diagnostics parse, serialize, and remain immutable', () {
      final reading = SensorReading.fromJson({
        'schemaVersion': '1.0',
        'eventId': 'event-diagnostics',
        'helmetId': 'H-01',
        'deviceTimestamp': 1000,
        'serverReceivedAt': 1100,
        'temperatureC': 27.4,
        'humidityPct': 58.2,
        'heatIndexC': 28.1,
        'gasWarmUp': true,
        'gasRaw': 1450,
        'gasAdcVoltage': 1.17,
        'gasSensorVoltage': 1.76,
        'gasDigitalThreshold': true,
        'accelXG': 0.02,
        'accelYG': -0.01,
        'accelZG': 0.99,
        'gyroXDegreesPerSecond': 0.6,
        'gyroYDegreesPerSecond': -0.4,
        'gyroZDegreesPerSecond': 0.2,
        'fallStatus': 'notEvaluated',
        'sensorFaults': ['mq7Uncalibrated', 'mq7HeaterStateUnknown'],
        'gpsStatus': 'invalid',
        'connectivity': 'online',
        'firmwareVersion': 'manual-test',
        'severity': 'unassessed',
      });

      expect(reading.heatIndexC, 28.1);
      expect(reading.gasRaw, 1450);
      expect(reading.gasDigitalThreshold, isTrue);
      expect(reading.gyroZDegreesPerSecond, 0.2);
      expect(reading.fallStatus, FallStatus.notEvaluated);
      expect(
        reading.sensorFaults,
        containsAll([
          SensorFault.mq7Uncalibrated,
          SensorFault.mq7HeaterStateUnknown,
        ]),
      );
      expect(
        () => reading.sensorFaults.add(SensorFault.dhtReadFailed),
        throwsUnsupportedError,
      );
      expect(reading.toJson()['gasRaw'], 1450);
      expect(reading.toJson()['gasAdcVoltage'], 1.17);
      expect(reading.toJson()['fallStatus'], 'notEvaluated');
      expect(reading.toJson()['severity'], 'unassessed');
    });

    test('manual sketch aliases normalize only at the ingestion boundary', () {
      final normalized = normalizeSensorReadingAtIngestion({
        'schemaVersion': '1.0',
        'eventId': 'manual-1',
        'helmetId': 'H-01',
        'deviceTimestamp': 1000,
        'serverReceivedAt': 1100,
        'temperature': 27.4,
        'humidity': 58.2,
        'heatIndex': 28.1,
        'accelX': 0.02,
        'accelY': -0.01,
        'accelZ': 0.99,
        'gyroX': 0.6,
        'gyroY': -0.4,
        'gyroZ': 0.2,
        'mq7Raw': 1450,
        'mq7AdcVoltage': 1.17,
        'mq7Voltage': 1.76,
        'mq7Digital': 0,
        'mpuValid': true,
        'dhtValid': true,
        'mq7Valid': true,
        'connectivity': 'online',
        'firmwareVersion': 'manual-test',
      });
      final reading = SensorReading.fromJson(normalized);

      expect(normalized, isNot(contains('temperature')));
      expect(normalized, isNot(contains('mq7Voltage')));
      expect(normalized, isNot(contains('mq7Digital')));
      expect(reading.temperatureC, 27.4);
      expect(reading.humidityPct, 58.2);
      expect(reading.gasRaw, 1450);
      expect(reading.gasAdcVoltage, 1.17);
      expect(reading.gasSensorVoltage, 1.76);
      expect(reading.gasDigitalThreshold, isTrue);
      expect(reading.gasPpm, isNull);
      expect(reading.gasWarmUp, isTrue);
      expect(reading.fallStatus, FallStatus.notEvaluated);
      expect(reading.location, isNull);
      expect(reading.batteryPct, isNull);
      expect(reading.severity, SafetySeverity.unassessed);
      expect(
        reading.sensorFaults,
        containsAll([
          SensorFault.mq7Uncalibrated,
          SensorFault.mq7HeaterStateUnknown,
          SensorFault.gpsUnavailable,
          SensorFault.batteryUnavailable,
        ]),
      );
    });

    test('sensor ranges and finite values are enforced', () {
      Map<String, dynamic> readingJson(Object? temperature) => {
        'schemaVersion': '1.0',
        'eventId': 'event-1',
        'helmetId': 'H-01',
        'deviceTimestamp': 1000,
        'serverReceivedAt': 1100,
        'temperatureC': temperature,
        'gasWarmUp': false,
        'gpsStatus': 'acquiring',
        'connectivity': 'online',
        'firmwareVersion': '1.0.0',
        'severity': 'safe',
      };

      expect(
        () => SensorReading.fromJson(readingJson(81)),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => SensorReading.fromJson(readingJson(double.nan)),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => SensorReading.fromJson({...readingJson(36), 'batteryPct': 50.5}),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => SensorReading.fromJson({...readingJson(36), 'gasPpm': 301}),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => SensorReading.fromJson({...readingJson(36), 'gasRaw': 4096}),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () =>
            SensorReading.fromJson({...readingJson(36), 'gasAdcVoltage': -0.1}),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => SensorReading.fromJson({
          ...readingJson(36),
          'gasWarmUp': true,
          'gasPpm': 100,
        }),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => normalizeSensorReadingAtIngestion({'mq7Digital': 2}),
        throwsA(isA<ModelValidationException>()),
      );
    });

    test('GPS rejects invalid 0,0 sentinel and invalid HDOP', () {
      expect(
        () => GPSLocation(
          latitudeDegrees: 0,
          longitudeDegrees: 0,
          capturedAt: DateTime.utc(2026),
          isLastKnown: false,
        ),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => GPSLocation(
          latitudeDegrees: 31.4,
          longitudeDegrees: 74.3,
          hdop: 6,
          capturedAt: DateTime.utc(2026),
          isLastKnown: false,
        ),
        throwsA(isA<ModelValidationException>()),
      );
    });

    test('numeric alert evidence requires explicit units', () {
      expect(
        () => SafetyAlert(
          alertId: 'alert-1',
          eventId: 'event-1',
          helmetId: 'H-01',
          siteId: 'site-1',
          type: AlertType.gas,
          severity: SafetySeverity.warning,
          sensorValue: 101,
          deviceTimestamp: DateTime.utc(2026),
          serverReceivedAt: DateTime.utc(2026),
          status: AlertStatus.created,
        ),
        throwsA(isA<ModelValidationException>()),
      );
    });

    test('alerts accept only warning or critical severity', () {
      SafetyAlert build(SafetySeverity severity) => SafetyAlert(
        alertId: 'alert-1',
        eventId: 'event-1',
        helmetId: 'H-01',
        siteId: 'site-1',
        type: AlertType.sensorFault,
        severity: severity,
        evidence: const {'faultCode': 1},
        deviceTimestamp: DateTime.utc(2026),
        serverReceivedAt: DateTime.utc(2026),
        status: AlertStatus.created,
      );

      expect(
        () => build(SafetySeverity.safe),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => build(SafetySeverity.unassessed),
        throwsA(isA<ModelValidationException>()),
      );
      expect(build(SafetySeverity.warning).severity, SafetySeverity.warning);
      expect(build(SafetySeverity.critical).severity, SafetySeverity.critical);
    });

    test('all approved alert types parse with immutable evidence', () {
      for (final type in AlertType.values) {
        final rawType = type == AlertType.sensorFault
            ? 'sensor_fault'
            : type.name;
        final alert = SafetyAlert.fromJson({
          'schemaVersion': '1.0',
          'alertId': 'alert-${type.name}',
          'eventId': 'event-${type.name}',
          'helmetId': 'H-01',
          'siteId': 'site-1',
          'workerId': 'worker-1',
          'alertType': rawType,
          'severity': 'warning',
          'evidence': {'confirmed': 1},
          'deviceTimestamp': 1,
          'serverReceivedAt': 2,
          'status': 'created',
        });
        expect(alert.type, type);
        expect(() => alert.evidence['tampered'] = 1, throwsUnsupportedError);
      }
    });

    test('acknowledged and resolved states require backend audit fields', () {
      Map<String, dynamic> record(String status) => {
        'schemaVersion': '1.0',
        'alertId': 'alert-1',
        'eventId': 'event-1',
        'helmetId': 'H-01',
        'siteId': 'site-1',
        'workerId': 'worker-1',
        'alertType': 'fall',
        'severity': 'critical',
        'evidence': {'impactG': 3.2},
        'deviceTimestamp': 1,
        'serverReceivedAt': 2,
        'status': status,
      };

      expect(
        () => SafetyAlert.fromJson(record('acknowledged')),
        throwsA(isA<ModelValidationException>()),
      );
      expect(
        () => SafetyAlert.fromJson({
          ...record('resolved'),
          'acknowledgedBy': 'supervisor-1',
          'acknowledgedAt': 3,
        }),
        throwsA(isA<ModelValidationException>()),
      );
    });

    test('configuration thresholds must remain in safe logical order', () {
      expect(
        () => HelmetConfiguration(
          helmetId: 'H-01',
          configVersion: '1',
          temperatureWarningC: 50,
          temperatureCriticalC: 40,
          humidityWarningLowPct: 30,
          humidityCriticalLowPct: 20,
          humidityWarningHighPct: 80,
          humidityCriticalHighPct: 90,
          gasWarningPpm: 100,
          gasCriticalPpm: 200,
          fallImpactThresholdG: 2.5,
          fallDuplicateCooldownSeconds: 30,
          normalPollingIntervalSeconds: 5,
          gasWarmUpHours: 24,
          updatedAt: DateTime.utc(2026),
          updatedBy: 'admin-1',
        ),
        throwsA(isA<ModelValidationException>()),
      );
    });
  });
}
