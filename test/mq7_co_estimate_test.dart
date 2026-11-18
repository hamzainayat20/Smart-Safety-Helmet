import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/firebase_realtime_repositories.dart';
import 'package:smart_safety/domain/mq7_co_estimate.dart';
import 'package:smart_safety/presentation/live_sensor_diagnostics.dart';

import 'live_sensor_diagnostics_test.dart' show host, rtdbCurrent;

void main() {
  group('estimateMq7Co', () {
    test('no baseline configured gives no number', () {
      final e = estimateMq7Co(raw: 2800, cleanAirRaw: null);
      expect(e.kind, Mq7EstimateKind.noBaseline);
      expect(e.ppm, isNull);
      expect(e.label, isNot(contains(RegExp(r'\d'))));
    });

    test('baseline value itself is below the rated range', () {
      final e = estimateMq7Co(raw: 2700, cleanAirRaw: 2700);
      expect(e.kind, Mq7EstimateKind.belowRange);
      expect(e.ppm, isNull);
      expect(e.label, 'Below 20 ppm (rated range 20–2000)');
    });

    test('values inside the rated range follow the datasheet curve', () {
      // Reference values computed independently from the same formula.
      final cases = {3950: 25.6, 4000: 41.9, 4058: 99.3, 4080: 165.1};
      for (final MapEntry(key: raw, value: expected) in cases.entries) {
        final e = estimateMq7Co(raw: raw, cleanAirRaw: 2700);
        expect(e.kind, Mq7EstimateKind.inRange, reason: '$raw');
        expect(e.ppm, closeTo(expected, 0.2), reason: '$raw');
        expect(e.label, '≈ ${expected.round()} ppm');
      }
    });

    test('estimate rises as the raw reading rises', () {
      double? at(int raw) => estimateMq7Co(raw: raw, cleanAirRaw: 2700).ppm;
      expect(at(4000)!, lessThan(at(4040)!));
      expect(at(4040)!, lessThan(at(4080)!));
    });

    test('above 2000 ppm is reported as out of range, not as a number', () {
      final e = estimateMq7Co(raw: 4000, cleanAirRaw: 500);
      expect(e.kind, Mq7EstimateKind.aboveRange);
      expect(e.ppm, isNull);
    });

    test('a saturated ADC never produces an estimate', () {
      for (final raw in [4090, 4095]) {
        expect(
          estimateMq7Co(raw: raw, cleanAirRaw: 2700).kind,
          Mq7EstimateKind.saturated,
        );
      }
    });

    test('unconvertible readings are rejected', () {
      expect(
        estimateMq7Co(raw: 0, cleanAirRaw: 2700).kind,
        Mq7EstimateKind.invalidInput,
      );
      expect(
        estimateMq7Co(raw: null, cleanAirRaw: 2700).kind,
        Mq7EstimateKind.invalidInput,
      );
    });

    test('baseline define parsing', () {
      expect(parseMq7CleanAirRaw(''), isNull);
      expect(parseMq7CleanAirRaw('abc'), isNull);
      expect(parseMq7CleanAirRaw('0'), isNull);
      expect(parseMq7CleanAirRaw('4095'), isNull);
      expect(parseMq7CleanAirRaw(' 2700 '), 2700);
    });
  });

  group('diagnostics display', () {
    final now = DateTime.utc(2026, 11, 18, 13);

    Future<void> pump(WidgetTester tester, {required int raw, int? base}) {
      final reading = parseCurrentReadingRecord(
        rtdbCurrent(
          helmetId: 'helmet001',
          eventId: 'e-$raw',
          received: now,
          mq7Raw: raw,
        ),
        'helmet001',
      )!;
      return tester.pumpWidget(
        host(
          LiveSensorDiagnostics(
            reading: reading,
            nowUtc: now,
            mq7CleanAirRaw: base,
          ),
        ),
      );
    }

    testWidgets('shows the clearly labelled estimate next to the raw value', (
      tester,
    ) async {
      await pump(tester, raw: 4058, base: 2700);
      expect(find.text('Estimated CO (uncalibrated)'), findsOneWidget);
      expect(find.text('≈ 99 ppm'), findsOneWidget);
      expect(find.text('4058 (Raw ADC — not ppm)'), findsOneWidget);
      expect(
        find.textContaining('never used for safety status or alerts'),
        findsOneWidget,
      );
    });

    testWidgets('without a baseline it explains instead of guessing', (
      tester,
    ) async {
      await pump(tester, raw: 2800);
      expect(
        find.text('Not set up (needs a clean-air baseline)'),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'≈ \d+ ppm')), findsNothing);
    });
  });
}
