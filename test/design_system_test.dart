import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/presentation/design_system/component_gallery.dart';
import 'package:smart_safety/presentation/design_system/design_system.dart';
import 'package:smart_safety/presentation/monitoring_state.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget host(Widget child, {Size? size, double textScale = 1}) => MediaQuery(
  data: MediaQueryData(
    size: size ?? const Size(400, 800),
    textScaler: TextScaler.linear(textScale),
  ),
  child: MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

/// Every non-icon text span currently on screen.
List<TextStyle> visibleTextStyles(WidgetTester tester) {
  final styles = <TextStyle>[];
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    paragraph.text.visitChildren((span) {
      final style = span.style;
      if (style != null &&
          style.fontSize != null &&
          style.fontFamily != 'MaterialIcons') {
        styles.add(style);
      }
      return true;
    });
  }
  return styles;
}

void main() {
  group('tokens', () {
    test('every type style meets the 14sp floor (NFR-US-04)', () {
      for (final entry in AppTypography.all.entries) {
        expect(
          entry.value.fontSize,
          greaterThanOrEqualTo(AppTypography.minimumFontSize),
          reason: entry.key,
        );
      }
    });

    test('theme text styles never fall below 14sp', () {
      final theme = buildAppTheme().textTheme;
      final styles = {
        'displayLarge': theme.displayLarge,
        'displaySmall': theme.displaySmall,
        'headlineSmall': theme.headlineSmall,
        'titleLarge': theme.titleLarge,
        'titleMedium': theme.titleMedium,
        'titleSmall': theme.titleSmall,
        'bodyLarge': theme.bodyLarge,
        'bodyMedium': theme.bodyMedium,
        'bodySmall': theme.bodySmall,
        'labelLarge': theme.labelLarge,
        'labelMedium': theme.labelMedium,
        'labelSmall': theme.labelSmall,
      };
      for (final entry in styles.entries) {
        expect(entry.value?.fontSize, isNotNull, reason: entry.key);
        expect(
          entry.value!.fontSize,
          greaterThanOrEqualTo(14),
          reason: entry.key,
        );
      }
    });

    test('text colours meet WCAG AAA on their backgrounds', () {
      for (final background in [AppColors.surface, AppColors.canvas]) {
        expect(
          contrast(AppColors.textPrimary, background),
          greaterThanOrEqualTo(7),
        );
        expect(
          contrast(AppColors.textSecondary, background),
          greaterThanOrEqualTo(7),
        );
      }
      for (final background in [AppColors.ink, AppColors.inkRaised]) {
        expect(contrast(AppColors.onInk, background), greaterThanOrEqualTo(7));
        expect(
          contrast(AppColors.onInkMuted, background),
          greaterThanOrEqualTo(7),
        );
      }
      expect(
        contrast(AppColors.onPrimary, AppColors.primary),
        greaterThanOrEqualTo(7),
      );
      expect(
        contrast(AppColors.interactive, AppColors.surface),
        greaterThanOrEqualTo(7),
      );
      expect(
        contrast(AppColors.borderControl, AppColors.surface),
        greaterThanOrEqualTo(3),
      );
    });
  });

  group('safety status roles', () {
    test('each status meets contrast targets in every context', () {
      for (final status in SafetyStatus.values) {
        final p = status.palette;
        expect(
          contrast(p.text, p.tint),
          greaterThanOrEqualTo(7),
          reason: '$status text',
        );
        expect(
          contrast(p.strong, AppColors.surface),
          greaterThanOrEqualTo(3),
          reason: '$status strong',
        );
        expect(
          contrast(p.onInk, AppColors.ink),
          greaterThanOrEqualTo(7),
          reason: '$status onInk',
        );
        expect(
          contrast(p.onInk, AppColors.inkRaised),
          greaterThanOrEqualTo(7),
          reason: '$status onInk raised',
        );
      }
    });

    test('statuses are distinguishable without colour', () {
      final values = SafetyStatus.values;
      expect(values.map((s) => s.icon).toSet(), hasLength(values.length));
      expect(values.map((s) => s.label).toSet(), hasLength(values.length));
      expect(
        values.map((s) => s.palette.strong).toSet(),
        hasLength(values.length),
      );
    });

    test('only a safe monitoring state is ever shown as normal', () {
      for (final state in MonitoringState.values) {
        final status = safetyStatusForMonitoringState(state);
        expect(
          status == SafetyStatus.normal,
          state == MonitoringState.safe,
          reason: '$state -> $status',
        );
      }
      expect(
        safetyStatusForMonitoringState(MonitoringState.sensorFault),
        SafetyStatus.critical,
      );
      expect(
        safetyStatusForMonitoringState(MonitoringState.offline),
        SafetyStatus.offline,
      );
      expect(
        safetyStatusForMonitoringState(MonitoringState.stale),
        SafetyStatus.stale,
      );
      expect(
        safetyStatusForMonitoringState(MonitoringState.warmingUp),
        SafetyStatus.pending,
      );
      expect(
        safetyStatusForMonitoringState(MonitoringState.permissionDenied),
        SafetyStatus.unknown,
      );
      expect(
        safetyStatusForMonitoringState(MonitoringState.backendError),
        SafetyStatus.unknown,
      );
      expect(
        safetyStatusForMonitoringState(MonitoringState.empty),
        SafetyStatus.unknown,
      );
    });

    test('unassessed severity and unknown risk are never normal', () {
      expect(
        safetyStatusForSeverity(SafetySeverity.unassessed),
        SafetyStatus.unknown,
      );
      expect(
        safetyStatusForAssessmentRisk(AssessmentRisk.unknown),
        SafetyStatus.unknown,
      );
      expect(safetyStatusForSeverity(SafetySeverity.safe), SafetyStatus.normal);
      expect(
        safetyStatusForAssessmentRisk(AssessmentRisk.critical),
        SafetyStatus.critical,
      );
    });

    test('monitoringStateColor now comes from the status roles', () {
      expect(
        monitoringStateColor(MonitoringState.critical),
        SafetyStatus.critical.palette.strong,
      );
      expect(
        monitoringStateColor(MonitoringState.safe),
        SafetyStatus.normal.palette.strong,
      );
    });
  });

  group('components', () {
    testWidgets('StatusChip shows icon and text and announces the status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(const StatusChip(status: SafetyStatus.critical)),
      );

      expect(find.text('Critical'), findsOneWidget);
      expect(find.byIcon(SafetyStatus.critical.icon), findsOneWidget);
      expect(find.bySemanticsLabel('Status: Critical'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('SensorCard never shows a missing value as normal', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SensorCard(
            label: 'Battery',
            icon: Icons.battery_std_rounded,
            value: null,
            unit: SensorUnit.percent,
            status: SafetyStatus.normal,
          ),
        ),
      );

      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('No reading'), findsOneWidget);
      expect(find.text('Normal'), findsNothing);
      expect(find.byIcon(SafetyStatus.unknown.icon), findsOneWidget);
    });

    testWidgets('SensorCard formats value with unit and shows freshness', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SensorCard(
            label: 'Temperature',
            icon: Icons.thermostat_rounded,
            value: 31.24,
            unit: SensorUnit.degreesCelsius,
            status: SafetyStatus.normal,
            updatedAt: DateTime.now().toUtc().subtract(
              const Duration(minutes: 3),
            ),
          ),
        ),
      );

      expect(find.text('31.2 °C'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.textContaining('Updated'), findsOneWidget);
    });

    testWidgets('SensorCard labels stale readings as last known', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SensorCard(
            label: 'Gas level',
            icon: Icons.air_rounded,
            value: 80,
            unit: SensorUnit.partsPerMillion,
            status: SafetyStatus.stale,
          ),
        ),
      );

      expect(find.textContaining('Last known value'), findsOneWidget);
      expect(find.text('Stale'), findsOneWidget);
    });

    testWidgets('AppButton is 48dp tall and blocks taps while loading', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          Column(
            children: [
              AppButton(label: 'Acknowledge', onPressed: () => taps++),
              AppButton(
                key: const Key('busy'),
                label: 'Saving',
                loading: true,
                onPressed: () => taps++,
              ),
            ],
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(AppButton).first).height,
        greaterThanOrEqualTo(AppSizes.touchTarget),
      );
      await tester.tap(find.text('Acknowledge'));
      await tester.tap(find.text('Saving'), warnIfMissed: false);
      await tester.pump();

      expect(taps, 1);
      final busy = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('busy')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(busy.onPressed, isNull);
    });

    testWidgets('StateView offers retry and calls back', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        host(
          StateView(
            kind: StateViewKind.error,
            title: 'Service unavailable',
            message: 'Try again.',
            onAction: () => retried = true,
          ),
        ),
      );

      expect(find.text('Service unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('MonitoringStatePanel keeps its title, message and retry', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpWidget(
        host(
          MonitoringStatePanel(
            state: MonitoringState.backendError,
            title: 'Monitoring backend unavailable',
            onRetry: () async => retried++,
          ),
        ),
      );

      expect(find.text('Monitoring backend unavailable'), findsOneWidget);
      expect(
        find.text(monitoringStateDescription(MonitoringState.backendError)),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('ThresholdGauge announces a missing reading', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 200,
            child: ThresholdGauge(
              value: null,
              max: 100,
              warningAt: 40,
              status: SafetyStatus.unknown,
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel(RegExp('^No reading')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('MetricTile shows an unknown count as a dash, not zero', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const MetricTile(
            label: 'Low battery',
            value: null,
            icon: Icons.battery_alert_rounded,
          ),
        ),
      );

      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(
        find.bySemanticsLabel('Low battery: not available'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('component gallery', () {
    final reference = DateTime.utc(2026, 11, 9, 12);

    for (final size in const [Size(360, 640), Size(1280, 800)]) {
      testWidgets('renders without overflow at ${size.width.round()}dp', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: ComponentGalleryPage(referenceTime: reference),
          ),
        );
        // The gallery intentionally includes indeterminate loading indicators,
        // so waiting for every animation to settle would never complete.
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Component gallery'), findsOneWidget);
      });
    }

    testWidgets('survives 200% text scaling on a small phone', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: ComponentGalleryPage(referenceTime: reference),
          ),
        ),
      );
      // The gallery intentionally includes indeterminate loading indicators,
      // so waiting for every animation to settle would never complete.
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('no visible text is smaller than 14sp', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ComponentGalleryPage(referenceTime: reference),
        ),
      );
      // The gallery intentionally includes indeterminate loading indicators,
      // so waiting for every animation to settle would never complete.
      await tester.pump();

      final styles = visibleTextStyles(tester);
      expect(styles, isNotEmpty);
      for (final style in styles) {
        expect(
          style.fontSize,
          greaterThanOrEqualTo(AppTypography.minimumFontSize),
        );
      }
    });

    testWidgets('interactive controls are at least 48dp', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ComponentGalleryPage(referenceTime: reference),
        ),
      );
      // The gallery intentionally includes indeterminate loading indicators,
      // so waiting for every animation to settle would never complete.
      await tester.pump();

      for (final type in [FilledButton, OutlinedButton, IconButton]) {
        for (final element in find.byType(type).evaluate()) {
          final size = tester.getSize(find.byWidget(element.widget));
          expect(
            size.height,
            greaterThanOrEqualTo(AppSizes.touchTarget),
            reason: '$type',
          );
          expect(
            size.width,
            greaterThanOrEqualTo(AppSizes.touchTarget),
            reason: '$type',
          );
        }
      }
    });
  });
}
