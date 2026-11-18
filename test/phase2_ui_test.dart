import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/main.dart';
import 'package:smart_safety/presentation/assessment_text.dart';
import 'package:smart_safety/presentation/design_system/design_system.dart';
import 'package:smart_safety/presentation/formatters.dart';
import 'package:smart_safety/presentation/sensor_limits.dart';

/// Phase 2 regression tests: threshold classification, plain-language AI
/// explanations, timestamps, adaptive navigation, the helmet search that was
/// previously a dead control, and the 14sp text floor (NFR-US-04) on live
/// screens.
void main() {
  group('SensorLimits', () {
    const limits = SensorLimits.defaults;

    test('defaults mirror FYP Table 3.2 and are labelled as defaults', () {
      expect(limits.isConfigured, isFalse);
      expect(limits.sourceLabel, 'Default limits (Table 3.2)');
      expect(limits.temperature(39.9), SafetyStatus.normal);
      expect(limits.temperature(40), SafetyStatus.warning);
      expect(limits.temperature(50.1), SafetyStatus.critical);
      expect(limits.gas(99), SafetyStatus.normal);
      expect(limits.gas(100), SafetyStatus.warning);
      expect(limits.gas(250), SafetyStatus.critical);
      expect(limits.humidity(55), SafetyStatus.normal);
      expect(limits.humidity(25), SafetyStatus.warning);
      expect(limits.humidity(85), SafetyStatus.warning);
      expect(limits.humidity(15), SafetyStatus.critical);
      expect(limits.humidity(95), SafetyStatus.critical);
    });

    test('missing readings are never classified as normal', () {
      expect(limits.temperature(null), SafetyStatus.unknown);
      expect(limits.humidity(null), SafetyStatus.unknown);
      expect(limits.gas(null), SafetyStatus.unknown);
      expect(SensorLimits.battery(null), SafetyStatus.unknown);
    });

    test('a warming-up gas sensor is pending, not safe or dangerous', () {
      expect(limits.gas(250, warmingUp: true), SafetyStatus.pending);
      expect(limits.gas(10, warmingUp: true), SafetyStatus.pending);
    });

    test('battery is critical below 20% and a warning at or below 30%', () {
      expect(SensorLimits.battery(87), SafetyStatus.normal);
      expect(SensorLimits.battery(31), SafetyStatus.normal);
      expect(SensorLimits.battery(30), SafetyStatus.warning);
      expect(SensorLimits.battery(20), SafetyStatus.warning);
      expect(SensorLimits.battery(19), SafetyStatus.critical);
    });

    test('configured limits from Firebase take precedence over defaults', () {
      final configured = SensorLimits.fromConfiguration(
        HelmetConfiguration(
          helmetId: 'H-03',
          configVersion: 'v-test',
          temperatureWarningC: 35,
          temperatureCriticalC: 45,
          humidityWarningLowPct: 25,
          humidityCriticalLowPct: 15,
          humidityWarningHighPct: 70,
          humidityCriticalHighPct: 85,
          gasWarningPpm: 50,
          gasCriticalPpm: 150,
          fallImpactThresholdG: 2.5,
          fallDuplicateCooldownSeconds: 30,
          normalPollingIntervalSeconds: 5,
          gasWarmUpHours: 24,
          updatedAt: DateTime.utc(2026, 1, 1),
          updatedBy: 'supervisor-test',
        ),
      );

      expect(configured.isConfigured, isTrue);
      expect(configured.sourceLabel, 'Configured limits');
      expect(configured.temperature(38), SafetyStatus.warning);
      expect(SensorLimits.defaults.temperature(38), SafetyStatus.normal);
      expect(configured.gas(60), SafetyStatus.warning);
      expect(configured.humidity(75), SafetyStatus.warning);
    });

    test('reading labels are plain language', () {
      expect(readingStatusLabel(SafetyStatus.normal), 'Normal');
      expect(readingStatusLabel(SafetyStatus.warning), 'Elevated');
      expect(readingStatusLabel(SafetyStatus.critical), 'Dangerous');
      expect(readingStatusLabel(SafetyStatus.pending), 'Sensor warming up');
      expect(readingStatusLabel(SafetyStatus.unknown), 'No reading');
    });
  });

  group('describeReasonCode (FR-AI-09)', () {
    test('known AI reason codes are explained in plain language', () {
      expect(
        describeReasonCode('GAS_SENSOR_WARMING'),
        'The gas sensor is still warming up, so gas results are excluded.',
      );
      expect(
        describeReasonCode('FALL_DETECTED'),
        'The motion model detected a fall pattern.',
      );
    });

    test('unknown codes are still shown, never hidden', () {
      expect(describeReasonCode('NEW_MODEL_SIGNAL'), 'New model signal.');
      expect(describeReasonCode('___'), 'Unspecified reason.');
    });
  });

  test('formatUtcTimestamp renders an explicit UTC timestamp', () {
    expect(
      formatUtcTimestamp(DateTime.utc(2026, 3, 7, 9, 5, 2)),
      '2026-03-07 09:05:02 UTC',
    );
  });

  testWidgets('SensorCard with no value shows Unavailable, never Normal', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SensorCard(
            label: 'Temperature',
            icon: Icons.thermostat,
            value: null,
            unit: SensorUnit.degreesCelsius,
            status: SafetyStatus.normal,
          ),
        ),
      ),
    );

    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('No reading'), findsOneWidget);
    expect(find.text('Normal'), findsNothing);
  });

  group('adaptive navigation', () {
    Future<void> pumpSupervisor(WidgetTester tester, Size size) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MyApp(
          dependencies: AppDependencies.allMocks(
            initialUid: 'supervisor-demo',
            referenceTimeUtc: DateTime.now().toUtc(),
          ),
          splashDuration: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('phones use the bottom navigation bar', (tester) async {
      await pumpSupervisor(tester, const Size(400, 900));
      expect(find.byType(AppNavigationBar), findsOneWidget);
      expect(find.byType(AppNavigationRail), findsNothing);
    });

    testWidgets('tablets and desktop use the navigation rail', (tester) async {
      await pumpSupervisor(tester, const Size(1280, 900));
      expect(find.byType(AppNavigationRail), findsOneWidget);
      expect(find.byType(AppNavigationBar), findsNothing);
    });
  });

  testWidgets('helmet search filters the fleet list and can be cleared', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MyApp(
        dependencies: AppDependencies.allMocks(
          initialUid: 'supervisor-demo',
          referenceTimeUtc: DateTime.now().toUtc(),
        ),
        splashDuration: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Helmets').last);
    await tester.pumpAndSettle();
    expect(find.text('Helmet H-02'), findsOneWidget);
    expect(find.text('Helmet H-11'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'h-11');
    await tester.pumpAndSettle();
    expect(find.text('Helmet H-11'), findsOneWidget);
    expect(find.text('Helmet H-02'), findsNothing);

    await tester.enterText(find.byType(TextField), 'no-such-helmet');
    await tester.pumpAndSettle();
    expect(find.text('No matching helmets'), findsOneWidget);

    await tester.tap(find.text('Clear filters').last);
    await tester.pumpAndSettle();
    expect(find.text('Helmet H-02'), findsOneWidget);
    expect(find.text('Helmet H-11'), findsOneWidget);
  });

  group('text floor (NFR-US-04)', () {
    List<double> undersizedText(WidgetTester tester) {
      final sizes = <double>[];
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.byType(RichText),
      )) {
        paragraph.text.visitChildren((span) {
          final size = span.style?.fontSize;
          if (size != null && size < AppTypography.minimumFontSize) {
            sizes.add(size);
          }
          return true;
        });
      }
      return sizes;
    }

    for (final uid in ['supervisor-demo', 'worker-ali']) {
      testWidgets('$uid dashboard has no text below 14sp', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MyApp(
            dependencies: AppDependencies.allMocks(
              initialUid: uid,
              referenceTimeUtc: DateTime.now().toUtc(),
            ),
            splashDuration: Duration.zero,
          ),
        );
        await tester.pumpAndSettle();

        expect(undersizedText(tester), isEmpty);
      });
    }
  });
}
