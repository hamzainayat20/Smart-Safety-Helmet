import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/presentation/safety_assessment_card.dart';
import 'package:smart_safety/presentation/assessment_history_panel.dart';

Map<String, dynamic> canonicalAssessment({
  String eventId = 'event-1',
  String gasStatus = 'evaluated',
  bool outOfDistribution = false,
  String overallRisk = 'safe',
}) => {
  'schemaVersion': '1.0',
  'assessmentId': eventId,
  'eventId': eventId,
  'helmetId': 'H-03',
  'sourceSchemaVersion': '2.0',
  'deviceTimestamp': 1000,
  'sourceServerReceivedAt': 1100,
  'assessedAt': 1200,
  'modelBundleVersion': 'phase-a-1',
  'fall': {
    'status': 'evaluated',
    'probability': 0.04,
    'threshold': 0.46,
    'modelVersion': 'fall-1',
  },
  'gas': {
    'status': gasStatus,
    'classification': 'NoGas',
    'confidence': 0.91,
    'probabilities': {
      'Mixture': 0.0,
      'NoGas': 0.91,
      'Perfume': 0.0,
      'Smoke': 0.09,
    },
    'modelVersion': 'gas-1',
    'outOfDistribution': outOfDistribution,
  },
  'environment': {
    'status': 'evaluated',
    'temperatureRisk': 'normal',
    'humidityRisk': 'normal',
    'heatIndexRisk': 'normal',
  },
  'overallRisk': overallRisk,
  'reasonCodes': ['GAS_NO_GAS'],
  'recommendationCodes': ['NO_IMMEDIATE_ACTION', 'UNTRUSTED_TEXT'],
};

SensorReading reading({String eventId = 'event-1'}) => SensorReading(
  schemaVersion: '2.0',
  eventId: eventId,
  helmetId: 'H-03',
  deviceTimestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
  serverReceivedAt: DateTime.fromMillisecondsSinceEpoch(1100, isUtc: true),
  gasWarmUp: false,
  gpsStatus: GpsStatus.invalid,
  connectivity: ConnectivityStatus.online,
  firmwareVersion: 'test',
  severity: SafetySeverity.unassessed,
);

void main() {
  test(
    'canonical assessment parses model results and local recommendations',
    () {
      final assessment = SafetyAssessment.fromJson(canonicalAssessment());

      expect(assessment.status, InferenceStatus.completed);
      expect(assessment.overallRisk, AssessmentRisk.safe);
      expect(assessment.displayRisk, AssessmentRisk.safe);
      expect(assessment.gas.gasClass, GasClass.noGas);
      expect(assessment.gas.probabilities[GasClass.smoke], 0.09);
      expect(assessment.matchesReading(reading()), isTrue);
      expect(assessment.recommendations, [
        'No immediate action is indicated; continue normal monitoring.',
      ]);
    },
  );

  test('out-of-distribution result can never be displayed as safe', () {
    final assessment = SafetyAssessment.fromJson(
      canonicalAssessment(outOfDistribution: true),
    );

    expect(assessment.hasUsableInference, isFalse);
    expect(assessment.displayRisk, AssessmentRisk.unknown);
  });

  test('assessment serializes back to the canonical backend field names', () {
    final assessment = SafetyAssessment.fromJson(canonicalAssessment());
    final json = assessment.toJson();

    expect(json['eventId'], 'event-1');
    expect(json.containsKey('sourceEventId'), isFalse);
    expect(json.containsKey('status'), isFalse);
    expect((json['fall'] as Map)['status'], 'evaluated');
    expect((json['gas'] as Map)['classification'], 'NoGas');
    expect((json['environment'] as Map)['temperatureRisk'], 'normal');
  });

  test('assessment ID must equal its source event ID', () {
    final json = canonicalAssessment()..['assessmentId'] = 'different-event';

    expect(
      () => SafetyAssessment.fromJson(json),
      throwsA(isA<ModelValidationException>()),
    );
  });

  test(
    'assessment for an older source event does not match current reading',
    () {
      final assessment = SafetyAssessment.fromJson(canonicalAssessment());

      expect(assessment.matchesReading(reading(eventId: 'event-2')), isFalse);
    },
  );

  test('mock assessment repository preserves worker helmet scope', () async {
    final data = MockDataSet.currentDemo(
      referenceTimeUtc: DateTime.utc(2026, 8, 2, 12),
    );
    final repository = MockAssessmentRepository(data);
    final worker = data.users['worker-ali']!;

    final assessments = await repository.watchLatestAssessments(worker).first;

    expect(assessments.keys, {'H-03'});
  });

  testWidgets('missing current assessment is visibly pending, never safe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafetyAssessmentCard(reading: reading(), assessment: null),
        ),
      ),
    );

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('SAFE'), findsNothing);
    expect(
      find.text('Waiting for an assessment of the current sensor event.'),
      findsOneWidget,
    );
  });

  testWidgets('out-of-distribution assessment is visibly non-safe', (
    tester,
  ) async {
    final assessment = SafetyAssessment.fromJson(
      canonicalAssessment(outOfDistribution: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafetyAssessmentCard(
            reading: reading(),
            assessment: assessment,
          ),
        ),
      ),
    );

    expect(find.text('OUT OF RANGE'), findsOneWidget);
    expect(find.text('SAFE'), findsNothing);
  });

  testWidgets('assessment history shows risk, evidence, timestamp and advice', (
    tester,
  ) async {
    final data = MockDataSet.currentDemo(
      referenceTimeUtc: DateTime.utc(2026, 8, 2, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssessmentHistoryPanel(
            repository: MockAssessmentRepository(data),
            actor: data.users['worker-ali']!,
            helmetId: 'H-03',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('RECENT AI ASSESSMENTS'), findsOneWidget);
    expect(find.text('SAFE'), findsOneWidget);
    expect(find.textContaining('Fall:'), findsOneWidget);
    expect(find.textContaining('UTC'), findsOneWidget);
    expect(find.textContaining('No immediate action'), findsOneWidget);
  });
}
