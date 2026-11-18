import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/firebase_realtime_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/presentation/safety_assessment_card.dart';

const _received = 1795006264952;

SensorReading _reading(List<String> faults) => parseCurrentReadingRecord({
  'schemaVersion': '2.0',
  'eventId': 'helmet001_5ede0669_3',
  'helmetId': 'helmet001',
  'deviceTimestamp': _received - 150,
  'firmwareVersion': '0.3.0-staging',
  'temperatureC': 30.6,
  'humidityPct': 41.4,
  'heatIndexC': 30.6,
  'accelXG': 0.1,
  'accelYG': 0.04,
  'accelZG': 1.09,
  'gyroXDegreesPerSecond': 0.05,
  'gyroYDegreesPerSecond': 0.03,
  'gyroZDegreesPerSecond': 0.01,
  'mq7Raw': 2657,
  'mq7WarmUp': true,
  'mq135WarmUp': false,
  'sensorFaults': faults,
  'serverReceivedAt': _received,
  'connectivity': 'online',
  'severity': 'unassessed',
}, 'helmet001')!;

const _physicalFaults = [
  'batteryUnavailable',
  'gpsUnavailable',
  'mq135HeaterStateUnknown',
  'mq135ReadFailed',
  'mq135Uncalibrated',
  'mq7HeaterStateUnknown',
  'mq7Uncalibrated',
];

Map<String, dynamic> _environment(String risk) => {
  'status': risk == 'unavailable' ? 'unavailable' : 'evaluated',
  'temperatureRisk': risk,
  'humidityRisk': risk,
  'heatIndexRisk': risk,
};

SafetyAssessment _assessment({
  double fallProbability = 0.00003,
  Map<String, dynamic>? gas,
  String environmentRisk = 'normal',
  String overallRisk = 'unknown',
  List<String> reasons = const ['GAS_MODEL_UNAVAILABLE', 'SENSOR_FAULT'],
}) => SafetyAssessment.fromJson({
  'schemaVersion': '1.0',
  'assessmentId': 'helmet001_5ede0669_3',
  'eventId': 'helmet001_5ede0669_3',
  'helmetId': 'helmet001',
  'sourceSchemaVersion': '2.0',
  'deviceTimestamp': _received - 150,
  'sourceServerReceivedAt': _received,
  'assessedAt': _received + 300,
  'modelBundleVersion': 'phase-a-1',
  'fall': {
    'status': 'evaluated',
    'probability': fallProbability,
    'threshold': 0.46,
    'modelVersion': '2.0',
  },
  'gas': gas ?? {'status': 'unavailable'},
  'environment': _environment(environmentRisk),
  'overallRisk': overallRisk,
  'reasonCodes': reasons,
  'recommendationCodes': ['VERIFY_SENSORS'],
});

Future<void> _pump(
  WidgetTester tester,
  SensorReading reading,
  SafetyAssessment assessment,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SafetyAssessmentCard(reading: reading, assessment: assessment),
      ),
    ),
  ),
);

void main() {
  testWidgets('missing MQ-135 reads as a partial check, never safe', (
    tester,
  ) async {
    await _pump(tester, _reading(_physicalFaults), _assessment());

    expect(find.text('PARTIAL CHECK'), findsOneWidget);
    expect(find.textContaining('Gas was not assessed'), findsOneWidget);
    expect(find.text('Fall: No fall detected (0.0%)'), findsOneWidget);
    expect(find.text('Environment: Normal'), findsOneWidget);
    expect(find.text('Gas: Not assessed — MQ-135 not fitted'), findsOneWidget);
    expect(find.text('SAFE'), findsNothing);
    expect(find.text('UNKNOWN'), findsNothing);
  });

  testWidgets('a disconnected MQ-7 is named as the gas reason', (tester) async {
    await _pump(
      tester,
      _reading(const ['batteryUnavailable', 'gpsUnavailable', 'mq7ReadFailed']),
      _assessment(),
    );
    expect(find.text('Gas: Not assessed — MQ-7 not reading'), findsOneWidget);
  });

  testWidgets('a missing DHT22 is not a partial check', (tester) async {
    await _pump(
      tester,
      _reading([..._physicalFaults, 'dhtReadFailed']),
      _assessment(environmentRisk: 'unavailable'),
    );
    expect(
      find.text(
        'Environment: Not assessed — temperature/humidity sensor not reading',
      ),
      findsOneWidget,
    );
    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(find.text('PARTIAL CHECK'), findsNothing);
  });

  testWidgets('a detected fall stays critical', (tester) async {
    await _pump(
      tester,
      _reading(_physicalFaults),
      _assessment(
        fallProbability: 0.91,
        overallRisk: 'critical',
        reasons: const ['FALL_DETECTED', 'GAS_MODEL_UNAVAILABLE'],
      ),
    );
    expect(find.text('CRITICAL'), findsOneWidget);
    expect(find.text('Fall: Fall detected (91.0%)'), findsOneWidget);
    expect(find.text('PARTIAL CHECK'), findsNothing);
  });

  testWidgets('an environment warning is shown and is not partial', (
    tester,
  ) async {
    await _pump(
      tester,
      _reading(_physicalFaults),
      _assessment(
        environmentRisk: 'warning',
        overallRisk: 'warning',
        reasons: const ['HEAT_INDEX_WARNING', 'GAS_MODEL_UNAVAILABLE'],
      ),
    );
    expect(find.text('WARNING'), findsOneWidget);
    expect(find.text('Environment: Needs attention'), findsOneWidget);
    expect(find.text('PARTIAL CHECK'), findsNothing);
  });

  testWidgets('a genuinely produced gas class is shown', (tester) async {
    await _pump(
      tester,
      _reading(const ['batteryUnavailable', 'gpsUnavailable']),
      _assessment(
        overallRisk: 'safe',
        reasons: const ['GAS_NO_GAS'],
        gas: {
          'status': 'evaluated',
          'classification': 'NoGas',
          'confidence': 0.91,
          'probabilities': {
            'Mixture': 0.0,
            'NoGas': 0.91,
            'Perfume': 0.0,
            'Smoke': 0.09,
          },
          'modelVersion': 'gas-1',
          'outOfDistribution': false,
        },
      ),
    );
    expect(find.text('Gas: No gas'), findsOneWidget);
    expect(find.text('SAFE'), findsOneWidget);
  });
}
