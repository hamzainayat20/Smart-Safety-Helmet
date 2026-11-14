import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/main.dart';
import 'package:smart_safety/presentation/design_system/design_system.dart';

/// Redesign regression tests: trend classification and honesty, the
/// worker thumb-zone actions, the supervisor "Act now" queue, and motion
/// that switches off under the platform's reduce-motion setting.
void main() {
  group('trendDirection', () {
    test('reports rising, falling and steady series', () {
      expect(trendDirection([30, 32, 35, 38]), TrendDirection.rising);
      expect(trendDirection([90, 80, 70]), TrendDirection.falling);
      expect(trendDirection([50, 50, 50]), TrendDirection.steady);
    });

    test('treats noise smaller than the spread as steady', () {
      expect(trendDirection([20, 30, 20, 30, 21]), TrendDirection.steady);
    });

    test('a single reading has no direction', () {
      expect(trendDirection([42]), TrendDirection.steady);
      expect(trendDirection(const []), TrendDirection.steady);
    });
  });

  group('TrendSparkline', () {
    Future<void> pumpSparkline(WidgetTester tester, List<double> values) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: SizedBox(
                width: 240,
                child: TrendSparkline(
                  values: values,
                  status: SafetyStatus.warning,
                  warningAt: 40,
                ),
              ),
            ),
          ),
        );

    testWidgets('never draws a trend from fewer than two readings', (
      tester,
    ) async {
      await pumpSparkline(tester, const [41]);
      expect(
        find.descendant(
          of: find.byType(TrendSparkline),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(find.textContaining('readings'), findsNothing);
    });

    testWidgets('labels direction in text, not colour alone', (tester) async {
      await pumpSparkline(tester, const [36, 38, 40, 42]);
      expect(find.text('Rising • last 4 readings'), findsOneWidget);
    });
  });

  group('ValueChangeHighlight', () {
    Widget host(Object value, {required bool reduceMotion}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: ValueChangeHighlight(
          value: value,
          color: SafetyStatus.warning.palette.tint,
          child: Text('$value'),
        ),
      ),
    );

    testWidgets('animates once when the value changes', (tester) async {
      await tester.pumpWidget(host('41.0 °C', reduceMotion: false));
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpWidget(host('41.5 °C', reduceMotion: false));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('does not animate under reduced motion', (tester) async {
      await tester.pumpWidget(host('41.0 °C', reduceMotion: true));
      await tester.pumpWidget(host('41.5 °C', reduceMotion: true));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('worker home', () {
    Future<void> pumpWorker(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MyApp(
          dependencies: AppDependencies.allMocks(
            initialUid: 'worker-ali',
            referenceTimeUtc: DateTime.now().toUtc(),
          ),
          splashDuration: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('primary actions sit in the thumb-zone bar', (tester) async {
      await pumpWorker(tester);
      final details = find.byKey(const Key('worker-open-details'));
      final alerts = find.byKey(const Key('worker-open-alerts'));
      expect(details, findsOneWidget);
      expect(alerts, findsOneWidget);

      final nav = tester.getTopLeft(find.byType(AppNavigationBar));
      expect(tester.getBottomLeft(details).dy, lessThanOrEqualTo(nav.dy));
      expect(tester.getSize(details).height, greaterThanOrEqualTo(48));
    });

    testWidgets('View alerts opens the worker alert list', (tester) async {
      await pumpWorker(tester);
      await tester.tap(find.byKey(const Key('worker-open-alerts')));
      await tester.pumpAndSettle();
      expect(find.text('High Humidity'), findsOneWidget);
    });

    testWidgets('Sensor details opens the live sensor screen', (tester) async {
      await pumpWorker(tester);
      await tester.tap(find.byKey(const Key('worker-open-details')));
      await tester.pumpAndSettle();
      expect(find.text('Sensor Data'), findsOneWidget);
    });

    testWidgets('secondary readings are still shown honestly', (tester) async {
      await pumpWorker(tester);
      expect(find.text('87 %'), findsOneWidget);
      expect(find.text('Humidity'), findsOneWidget);
    });
  });

  group('supervisor Act now queue', () {
    Future<void> pumpSupervisor(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 2400));
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

    Finder keyStartingWith(String prefix) => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(prefix),
    );

    testWidgets('open alerts offer acknowledge and locate', (tester) async {
      await pumpSupervisor(tester);
      expect(find.text('Act now'), findsOneWidget);
      expect(keyStartingWith('attention-acknowledge-'), findsWidgets);
      expect(keyStartingWith('attention-locate-'), findsWidgets);
    });

    testWidgets('Acknowledge asks for confirmation before acting', (
      tester,
    ) async {
      await pumpSupervisor(tester);
      await tester.tap(keyStartingWith('attention-acknowledge-').first);
      await tester.pumpAndSettle();
      expect(find.text('Acknowledge alert?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Acknowledge alert?'), findsNothing);
    });

    testWidgets('Locate switches to the GPS map', (tester) async {
      await pumpSupervisor(tester);
      await tester.tap(keyStartingWith('attention-locate-').first);
      await tester.pumpAndSettle();
      expect(find.text('Worker Locations'), findsOneWidget);
    });
  });
}
