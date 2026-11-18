import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/presentation/design_system/design_system.dart';
import 'package:smart_safety/splash_screen.dart';

void main() {
  Widget app({
    Duration? duration = const Duration(seconds: 2),
    bool reduceMotion = false,
  }) => MaterialApp(
    theme: buildAppTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: SplashScreen(
      duration: duration,
      builder: (_) => const Scaffold(body: Text('Next screen')),
    ),
  );

  testWidgets('shows the brand, capabilities and startup state', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Smart Safety'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('AI risk'), findsOneWidget);
    expect(find.text('Starting up…'), findsOneWidget);
    expect(find.text('Next screen'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Next screen'), findsOneWidget);
  });

  testWidgets('the progress bar tracks the real splash timer', (tester) async {
    await tester.pumpWidget(app(duration: const Duration(seconds: 4)));
    double fill() => tester
        .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .widthFactor!;

    await tester.pump(const Duration(seconds: 1));
    expect(fill(), closeTo(0.25, 0.05));
    await tester.pump(const Duration(seconds: 2));
    expect(fill(), closeTo(0.75, 0.05));
  });

  testWidgets('without a duration it stays and shows no progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(app(duration: null));
    await tester.pumpAndSettle();
    expect(find.byType(FractionallySizedBox), findsNothing);
    expect(find.text('Next screen'), findsNothing);
  });

  testWidgets('reduce motion renders the final state with no animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(duration: const Duration(seconds: 2), reduceMotion: true),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Smart Safety'), findsOneWidget);
  });

  for (final size in const [Size(320, 568), Size(640, 360), Size(1280, 800)]) {
    testWidgets('lays out without overflow at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(duration: null));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
