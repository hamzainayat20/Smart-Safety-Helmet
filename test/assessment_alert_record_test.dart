import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/domain/models.dart';

// These records have exactly the shape written by
// functions/src/assessment_alerts.js (see functions/test/assessment_alerts.test.js).
// If they ever stop parsing, the whole alert list would fail to load.

Map<String, dynamic> _temperatureAlert() => {
  'schemaVersion': '1.0',
  'alertId': '7cb4ae008757f26f696135685e9de6cc8fc4bdde734e67cb5cfae599d1186ed8',
  'eventId': 'helmet001_5ede0669_3',
  'helmetId': 'helmet001',
  'siteId': 'site-main',
  'workerId': 'workerUid1',
  'alertType': 'temperature',
  'severity': 'warning',
  'sensorValue': 37.2,
  'unit': 'degreesCelsius',
  'evidence': {
    'temperatureC': 37.2,
    'humidityPct': 41.4,
    'heatIndexC': 36.4,
    'fallProbability': 0.00003,
    'fallThreshold': 0.46,
  },
  'deviceTimestamp': 1795006264802,
  'serverReceivedAt': 1795006265000,
  'status': 'created',
};

Map<String, dynamic> _fallAlert() => {
  'schemaVersion': '1.0',
  'alertId': 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
  'eventId': 'helmet001_5ede0669_9',
  'helmetId': 'helmet001',
  'siteId': 'site-main',
  'alertType': 'fall',
  'severity': 'critical',
  'evidence': {
    'temperatureC': 30.6,
    'humidityPct': 41.4,
    'heatIndexC': 30.6,
    'fallProbability': 0.91,
    'fallThreshold': 0.46,
  },
  'deviceTimestamp': 1795006264802,
  'serverReceivedAt': 1795006265000,
  'status': 'created',
};

void main() {
  test('assessment temperature alert parses with its measurement', () {
    final alert = SafetyAlert.fromJson(_temperatureAlert());
    expect(alert.type, AlertType.temperature);
    expect(alert.severity, SafetySeverity.warning);
    expect(alert.sensorValue, 37.2);
    expect(alert.unit, SensorUnit.degreesCelsius);
    expect(alert.threshold, isNull);
    expect(alert.workerId, 'workerUid1');
    expect(alert.status, AlertStatus.created);
    expect(alert.location, isNull);
    expect(alert.evidence['fallThreshold'], 0.46);
  });

  test('assessment fall alert parses without a fabricated measurement', () {
    final alert = SafetyAlert.fromJson(_fallAlert());
    expect(alert.type, AlertType.fall);
    expect(alert.severity, SafetySeverity.critical);
    expect(alert.sensorValue, isNull);
    expect(alert.unit, isNull);
    expect(alert.workerId, isNull);
    expect(alert.evidence['fallProbability'], 0.91);
  });
}
