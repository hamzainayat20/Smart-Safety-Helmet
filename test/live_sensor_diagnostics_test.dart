import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/application/dashboard_view_model.dart';
import 'package:smart_safety/data/firebase_realtime_repositories.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/domain/repositories.dart';
import 'package:smart_safety/presentation/live_sensor_diagnostics.dart';
import 'package:smart_safety/sensor_detail_screen.dart';

Map<String, Object?> rtdbCurrent({
  required String helmetId,
  required String eventId,
  required DateTime received,
  double? temperatureC = 29.4,
  double accelZG = 1.094,
  int? mq7Raw = 208,
  bool withWindow = true,
  List<String>? faults,
}) => {
  'schemaVersion': '2.0',
  'eventId': eventId,
  'helmetId': helmetId,
  'deviceTimestamp': received.millisecondsSinceEpoch - 150,
  'firmwareVersion': '0.3.0-staging',
  if (temperatureC != null) ...{
    'temperatureC': temperatureC,
    'humidityPct': 61.2,
    'heatIndexC': 31.8,
  },
  'accelXG': 0.04,
  'accelYG': -0.002,
  'accelZG': accelZG,
  'gyroXDegreesPerSecond': 0.012,
  'gyroYDegreesPerSecond': -0.02,
  'gyroZDegreesPerSecond': 0.005,
  'mq7Raw': ?mq7Raw,
  'mq7WarmUp': true,
  'mq135WarmUp': false,
  if (withWindow) ...{
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
    'windowEndTimestamp': received.millisecondsSinceEpoch - 350,
  },
  'sensorFaults':
      faults ??
      [
        'batteryUnavailable',
        'gpsUnavailable',
        'mq135HeaterStateUnknown',
        'mq135ReadFailed',
        'mq135Uncalibrated',
        'mq7HeaterStateUnknown',
        'mq7Uncalibrated',
      ],
  'serverReceivedAt': received.millisecondsSinceEpoch,
  'connectivity': 'online',
  'severity': 'unassessed',
};

/// Reading repository whose `watchLatestReadings` behaves like the RTDB
/// `onValue` listener: every raw snapshot pushed to [current] is parsed with
/// the production parser and emitted as the latest reading.
final class StreamingReadingRepository implements ReadingRepository {
  StreamingReadingRepository(this.helmetId);

  final String helmetId;
  final current = StreamController<Object?>.broadcast();

  @override
  Stream<bool> watchBackendConnection() => Stream.value(true);

  @override
  Stream<Map<String, SensorReading>> watchLatestReadings(UserProfile actor) =>
      current.stream.map<Map<String, SensorReading>>((value) {
        final reading = parseCurrentReadingRecord(value, helmetId);
        return reading == null
            ? const <String, SensorReading>{}
            : <String, SensorReading>{helmetId: reading};
      });

  @override
  Stream<List<SensorReading>> watchHelmetReadings(
    UserProfile actor,
    String helmetId,
  ) => Stream.value(const []);
}

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: app!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('values update each time the RTDB current stream emits', (
    tester,
  ) async {
    final source = StreamController<Object?>();
    addTearDown(source.close);
    final now = DateTime.utc(2026, 11, 17, 16);
    await tester.pumpWidget(
      host(
        StreamBuilder<Object?>(
          stream: source.stream,
          builder: (context, snapshot) {
            final reading = parseCurrentReadingRecord(
              snapshot.data,
              'helmet001',
            );
            return reading == null
                ? const Text('No current reading')
                : LiveSensorDiagnostics(reading: reading, nowUtc: now);
          },
        ),
      ),
    );
    expect(find.text('No current reading'), findsOneWidget);

    source.add(rtdbCurrent(helmetId: 'helmet001', eventId: 'e7', received: now));
    await tester.pump();
    expect(find.text('29.4 °C'), findsOneWidget);
    expect(find.text('1.094 g'), findsOneWidget);
    expect(find.text('208 (Raw ADC — not ppm)'), findsOneWidget);
    expect(find.text('100 samples at 50 Hz'), findsOneWidget);
    expect(find.text('e7'), findsOneWidget);

    source.add(
      rtdbCurrent(
        helmetId: 'helmet001',
        eventId: 'e8',
        received: now,
        temperatureC: 30.1,
        accelZG: 0.982,
        mq7Raw: 215,
      ),
    );
    await tester.pump();
    expect(find.text('30.1 °C'), findsOneWidget);
    expect(find.text('0.982 g'), findsOneWidget);
    expect(find.text('215 (Raw ADC — not ppm)'), findsOneWidget);
    expect(find.text('e8'), findsOneWidget);
    expect(find.text('29.4 °C'), findsNothing);
    expect(find.text('e7'), findsNothing);
  });

  testWidgets('sensor detail screen updates from the live repository stream', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = MockDataSet.currentDemo(referenceTimeUtc: DateTime.now().toUtc());
    final readings = StreamingReadingRepository('H-03');
    addTearDown(readings.current.close);
    final viewModel = DashboardViewModel(
      profile: data.users['supervisor-demo']!,
      dependencies: AppDependencies(
        authentication: MockAuthenticationRepository(data),
        users: MockUserRepository(data),
        sites: MockSiteRepository(data),
        helmets: MockHelmetRepository(data),
        readings: readings,
        alerts: MockAlertRepository(data),
        configuration: MockConfigurationRepository(data),
        dataSourceKind: DataSourceKind.deterministicMock,
      ),
    )..start();

    readings.current.add(
      rtdbCurrent(
        helmetId: 'H-03',
        eventId: 'H-03_live_1',
        received: DateTime.now().toUtc(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SensorDetailScreen(
          helmetId: 'H-03',
          workerName: 'Test Worker',
          viewModel: viewModel,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Live sensor diagnostics'), findsOneWidget);
    expect(find.text('H-03_live_1'), findsOneWidget);
    expect(find.text('1.094 g'), findsOneWidget);

    readings.current.add(
      rtdbCurrent(
        helmetId: 'H-03',
        eventId: 'H-03_live_2',
        received: DateTime.now().toUtc(),
        accelZG: 0.982,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('H-03_live_2'), findsOneWidget);
    expect(find.text('0.982 g'), findsOneWidget);
    expect(find.text('H-03_live_1'), findsNothing);
    viewModel.dispose();
  });

  testWidgets('missing values show Unavailable and faults in plain language', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 17, 16);
    final reading = parseCurrentReadingRecord(
      rtdbCurrent(
        helmetId: 'helmet001',
        eventId: 'partial',
        received: now,
        temperatureC: null,
        mq7Raw: null,
        withWindow: false,
        faults: [
          'batteryUnavailable',
          'dhtReadFailed',
          'fallWindowUnavailable',
          'gpsUnavailable',
          'mq135ReadFailed',
          'mq7ReadFailed',
        ],
      ),
      'helmet001',
    )!;
    await tester.pumpWidget(
      host(LiveSensorDiagnostics(reading: reading, nowUtc: now)),
    );

    // Temperature, humidity, heat index, MQ-7, estimated CO, MQ-135, window,
    // window end, AI fall check and AI gas class are all unavailable.
    expect(find.text('Unavailable'), findsNWidgets(10));
    expect(find.textContaining('0 °C'), findsNothing);
    expect(find.text('Advanced fall-model features'), findsNothing);
    for (final label in [
      'Temperature/humidity sensor (DHT22) not reading',
      'Gas sensor (MQ-7) not reading',
      'Air-quality sensor (MQ-135) not fitted',
      'Fall-model window not ready',
      'GPS not fitted',
      'Battery monitor not fitted',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.textContaining('mq7ReadFailed'), findsNothing);
    // Raw MQ-7 is never presented as a ppm concentration.
    expect(find.textContaining(RegExp(r'\d+(\.\d+)? ppm')), findsNothing);
  });

  testWidgets('stale readings are labelled with their last update time', (
    tester,
  ) async {
    final received = DateTime.utc(2026, 11, 17, 16);
    final reading = parseCurrentReadingRecord(
      rtdbCurrent(helmetId: 'helmet001', eventId: 'old', received: received),
      'helmet001',
    )!;
    await tester.pumpWidget(
      host(
        LiveSensorDiagnostics(
          reading: reading,
          isLive: false,
          nowUtc: received.add(const Duration(minutes: 5)),
        ),
      ),
    );
    expect(find.text('Stale · last updated 5m ago'), findsWidgets);
  });

  testWidgets('advanced fall features stay collapsed until requested', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 17, 16);
    final reading = parseCurrentReadingRecord(
      rtdbCurrent(helmetId: 'helmet001', eventId: 'e1', received: now),
      'helmet001',
    )!;
    await tester.pumpWidget(
      host(
        LiveSensorDiagnostics(reading: reading, nowUtc: now),
        reduceMotion: true,
      ),
    );
    expect(find.text('acc_mean'), findsNothing);
    final toggle = find.text('Advanced fall-model features');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    for (final key in FallWindowFeatures.featureKeys) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
    expect(find.text('0.35 g/s'), findsOneWidget);
    expect(find.text('0.45 °/s'), findsOneWidget);
    expect(find.text('1.0995 g'), findsOneWidget);
  });

  testWidgets('AI results appear only when the backend produced them', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 17, 16);
    final reading = parseCurrentReadingRecord(
      rtdbCurrent(helmetId: 'helmet001', eventId: 'e1', received: now),
      'helmet001',
    )!;
    Map<String, dynamic> assessmentJson({required bool gasEvaluated}) => {
      'schemaVersion': '1.0',
      'assessmentId': 'e1',
      'eventId': 'e1',
      'helmetId': 'helmet001',
      'sourceSchemaVersion': '2.0',
      'deviceTimestamp': reading.deviceTimestamp.millisecondsSinceEpoch,
      'sourceServerReceivedAt': reading.serverReceivedAt.millisecondsSinceEpoch,
      'assessedAt': reading.serverReceivedAt.millisecondsSinceEpoch + 100,
      'modelBundleVersion': 'phase-a-1',
      'fall': {
        'status': 'evaluated',
        'probability': 0.00003,
        'threshold': 0.46,
        'modelVersion': '2.0',
      },
      'gas': gasEvaluated
          ? {
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
            }
          : {'status': 'unavailable'},
      'environment': {
        'status': 'evaluated',
        'temperatureRisk': 'normal',
        'humidityRisk': 'normal',
        'heatIndexRisk': 'normal',
      },
      'overallRisk': 'unknown',
      'reasonCodes': ['GAS_MODEL_UNAVAILABLE'],
      'recommendationCodes': ['VERIFY_SENSORS'],
    };

    await tester.pumpWidget(
      host(
        LiveSensorDiagnostics(
          reading: reading,
          nowUtc: now,
          assessment: SafetyAssessment.fromJson(
            assessmentJson(gasEvaluated: false),
          ),
        ),
      ),
    );
    expect(find.text('0% fall probability (alert at 46%)'), findsOneWidget);
    expect(find.textContaining('No gas'), findsNothing);

    await tester.pumpWidget(
      host(
        LiveSensorDiagnostics(
          reading: reading,
          nowUtc: now,
          assessment: SafetyAssessment.fromJson(
            assessmentJson(gasEvaluated: true),
          ),
        ),
      ),
    );
    expect(find.text('No gas (91% confidence)'), findsOneWidget);
  });
}
