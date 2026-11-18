import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/application/dashboard_view_model.dart';
import 'package:smart_safety/application/gps_map_view_model.dart';
import 'package:smart_safety/application/simulated_gps.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/gps_map_page.dart';
import 'package:smart_safety/platform/maps/maps_runtime.dart';

// A public test coordinate used only by these tests.
const testLatitude = '31.5204';
const testLongitude = '74.3587';

SimulatedLocationProvider activeProvider({DateTime? createdAt}) =>
    StaticSimulatedLocationProvider(
      SimulatedGpsConfig.parse(
        enabled: true,
        latitude: testLatitude,
        longitude: testLongitude,
      ),
      clock: () => createdAt ?? DateTime.utc(2026, 11, 18, 8),
    );

void main() {
  final now = DateTime.utc(2026, 8, 3, 12);

  group('SimulatedGpsConfig', () {
    test('is disabled by default in every build without dart-defines', () {
      final config = SimulatedGpsConfig.fromEnvironment();
      expect(config.requested, isFalse);
      expect(config.active, isFalse);
      expect(
        simulatedLocationProviderFromEnvironment(),
        isA<DisabledSimulatedLocationProvider>(),
      );
    });

    test('a disabled flag ignores any coordinates', () {
      final config = SimulatedGpsConfig.parse(
        enabled: false,
        latitude: testLatitude,
        longitude: testLongitude,
      );
      expect(config.active, isFalse);
      expect(config.problem, isNull);
    });

    test('accepts a valid public test coordinate', () {
      final config = SimulatedGpsConfig.parse(
        enabled: true,
        latitude: ' $testLatitude ',
        longitude: testLongitude,
      );
      expect(config.active, isTrue);
      expect(config.latitude, 31.5204);
      expect(config.longitude, 74.3587);
    });

    test('rejects missing, non-numeric, NaN, infinite, out-of-range and 0,0', () {
      const invalid = <(String, String)>[
        ('', ''),
        ('', testLongitude),
        ('abc', testLongitude),
        ('NaN', testLongitude),
        (testLatitude, 'Infinity'),
        ('-Infinity', testLongitude),
        ('90.0001', testLongitude),
        ('-91', testLongitude),
        (testLatitude, '180.5'),
        (testLatitude, '-181'),
        ('0', '0'),
        ('-0.0', '0.0'),
      ];
      for (final (latitude, longitude) in invalid) {
        final config = SimulatedGpsConfig.parse(
          enabled: true,
          latitude: latitude,
          longitude: longitude,
        );
        expect(config.requested, isTrue, reason: '$latitude,$longitude');
        expect(config.active, isFalse, reason: '$latitude,$longitude');
        expect(config.problem, isNotNull, reason: '$latitude,$longitude');
        final provider = StaticSimulatedLocationProvider(config);
        expect(provider.isActive, isFalse);
        expect(provider.configurationProblem, config.problem);
      }
    });
  });

  group('StaticSimulatedLocationProvider', () {
    test('returns the configured coordinate with a fixed, non-live timestamp', () {
      final created = DateTime.utc(2026, 11, 18, 8);
      final provider = activeProvider(createdAt: created);
      final helmet = _helmet('helmet001');
      final first = provider.locationFor(helmet, 0)!;
      final again = provider.locationFor(helmet, 0)!;
      expect(first.latitudeDegrees, 31.5204);
      expect(first.longitudeDegrees, 74.3587);
      expect(first.hdop, isNull, reason: 'no fake accuracy is claimed');
      expect(first.isLastKnown, isFalse);
      expect(first.capturedAt, created);
      expect(again.capturedAt, first.capturedAt);
    });

    test('offsets additional helmets so markers never overlap', () {
      final provider = activeProvider();
      final second = provider.locationFor(_helmet('H-2'), 1)!;
      expect(second.latitudeDegrees, closeTo(31.52055, 1e-9));
      expect(second.longitudeDegrees, 74.3587);
    });

    test('the disabled provider never produces a location', () {
      const provider = DisabledSimulatedLocationProvider();
      expect(provider.isActive, isFalse);
      expect(provider.locationFor(_helmet('helmet001'), 0), isNull);
    });
  });

  group('GpsMapViewModel with simulated GPS', () {
    test('disabled simulation keeps a helmet without GPS unpositioned', () async {
      final fixture = _Fixture(now, removeLocationOf: 'H-03');
      final dashboard = fixture.dashboard('worker-ali');
      await _settleStreams();
      final map = GpsMapViewModel(dashboard: dashboard, clock: () => now);

      expect(map.simulationActive, isFalse);
      expect(map.positionedItems, isEmpty);
      expect(map.items.single.markerState, HelmetMapState.gpsLost);
      expect(map.items.single.isSimulatedLocation, isFalse);
      expect(map.focusForWorker('H-03'), isNull);

      map.dispose();
      dashboard.dispose();
      fixture.dispose();
    });

    test('active simulation places the helmet at the labelled demo location', () async {
      final fixture = _Fixture(now, removeLocationOf: 'H-03');
      final dashboard = fixture.dashboard('worker-ali');
      await _settleStreams();
      final map = GpsMapViewModel(
        dashboard: dashboard,
        clock: () => now,
        simulatedLocations: activeProvider(),
      );

      final item = map.positionedItems.single;
      expect(map.simulationActive, isTrue);
      expect(item.helmet.helmetId, 'H-03');
      expect(item.isSimulatedLocation, isTrue);
      expect(item.location!.latitudeDegrees, 31.5204);
      expect(item.location!.longitudeDegrees, 74.3587);
      // The colour comes from the real telemetry state, never "valid fix".
      expect(item.markerState, isNot(HelmetMapState.gpsLost));
      final focus = map.focusForWorker('H-03')!;
      expect(focus.location.latitudeDegrees, 31.5204);
      expect(focus.reason, MapFocusReason.workerSelection);

      // Nothing is written back: the stored reading still has no location.
      expect(fixture.data.readings['H-03']!.location, isNull);
      expect(dashboard.readingFor('H-03')!.location, isNull);
      expect(dashboard.readingFor('H-03')!.toJson().containsKey('location'), isFalse);

      map.dispose();
      dashboard.dispose();
      fixture.dispose();
    });

    test('a real GPS fix always wins over the simulation', () async {
      final fixture = _Fixture(now);
      final dashboard = fixture.dashboard('worker-ali');
      await _settleStreams();
      final real = dashboard.readingFor('H-03')!.location!;
      final map = GpsMapViewModel(
        dashboard: dashboard,
        clock: () => now,
        simulatedLocations: activeProvider(),
      );

      final item = map.positionedItems.single;
      expect(item.isSimulatedLocation, isFalse);
      expect(item.location!.latitudeDegrees, real.latitudeDegrees);

      map.dispose();
      dashboard.dispose();
      fixture.dispose();
    });

    test('stale telemetry shows a stale simulated marker', () async {
      final fixture = _Fixture(now, removeLocationOf: 'H-03');
      final dashboard = DashboardViewModel(
        profile: fixture.data.users['worker-ali']!,
        dependencies: fixture.dependencies,
        clock: () => now.add(const Duration(minutes: 10)),
        freshnessTick: const Duration(hours: 1),
      )..start();
      await _settleStreams();
      final map = GpsMapViewModel(
        dashboard: dashboard,
        clock: () => now.add(const Duration(minutes: 10)),
        simulatedLocations: activeProvider(),
      );

      expect(map.positionedItems.single.markerState, HelmetMapState.stale);

      map.dispose();
      dashboard.dispose();
      fixture.dispose();
    });

    test('authorization rules are unchanged by simulation', () async {
      final fixture = _Fixture(now, removeLocationOf: 'H-03');
      final dashboard = fixture.dashboard('worker-ali');
      await _settleStreams();
      final map = GpsMapViewModel(
        dashboard: dashboard,
        clock: () => now,
        simulatedLocations: activeProvider(),
      );
      expect(map.items.map((item) => item.helmet.helmetId), ['H-03']);

      map.dispose();
      dashboard.dispose();
      fixture.dispose();
    });

    test('app dependencies default to no simulation', () {
      final dependencies = AppDependencies.allMocks(
        referenceTimeUtc: DateTime.utc(2026, 8, 3, 12),
      );
      expect(dependencies.simulatedLocations.isActive, isFalse);
    });
  });

  group('GpsMapPage', () {
    Future<_PageHarness> pumpPage(
      WidgetTester tester, {
      SimulatedLocationProvider? simulatedLocations,
      MapsRuntimeResult runtimeResult = const MapsRuntimeResult.ready(),
    }) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture(
        now,
        removeLocationOf: 'H-03',
        simulatedLocations:
            simulatedLocations ?? const DisabledSimulatedLocationProvider(),
      );
      final dashboard = fixture.dashboard('worker-ali');
      final focus = MapFocusController();
      final harness = _PageHarness(fixture, dashboard, focus);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GpsMapPage(
              viewModel: dashboard,
              onSignOut: () {},
              focusController: focus,
              mapsRuntime: _ImmediateMapsRuntime(runtimeResult),
              mapBuilder: (_, items, _, _, _) {
                harness.mappedItems = items;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      return harness;
    }

    testWidgets('disabled simulation keeps GPS Lost and builds no map', (
      tester,
    ) async {
      final harness = await pumpPage(tester);

      expect(find.text('Waiting for a valid GPS fix'), findsOneWidget);
      expect(find.textContaining('GPS Lost'), findsWidgets);
      expect(find.textContaining('Coordinates unavailable'), findsOneWidget);
      expect(find.textContaining('Simulated GPS'), findsNothing);
      expect(find.byKey(const Key('simulated-gps-badge')), findsNothing);
      expect(harness.mappedItems, isNull);

      await harness.dispose(tester);
    });

    testWidgets('active simulation shows one clearly labelled demo marker', (
      tester,
    ) async {
      final harness = await pumpPage(
        tester,
        simulatedLocations: activeProvider(),
      );

      expect(harness.mappedItems, hasLength(1));
      expect(harness.mappedItems!.single.isSimulatedLocation, isTrue);
      expect(find.text('Simulated GPS (demo location)'), findsOneWidget);
      expect(find.byKey(const Key('simulated-gps-badge')), findsOneWidget);
      expect(find.text('Simulated GPS — demo location'), findsOneWidget);
      expect(find.textContaining('(simulated GPS)'), findsOneWidget);
      expect(find.textContaining('Demo location 31.5204'), findsOneWidget);
      expect(find.textContaining('Waiting for a valid GPS fix'), findsNothing);

      // Selecting the worker centres the map on the demo location.
      await tester.tap(find.textContaining('Demo location 31.5204'));
      await tester.pumpAndSettle();
      expect(harness.focus.current?.helmetId, 'H-03');
      expect(harness.focus.current?.location.latitudeDegrees, 31.5204);
      expect(
        find.text('Simulated GPS • demo location, not from helmet hardware'),
        findsWidgets,
      );

      await harness.dispose(tester);
    });

    testWidgets('invalid simulation configuration is reported, not used', (
      tester,
    ) async {
      final harness = await pumpPage(
        tester,
        simulatedLocations: StaticSimulatedLocationProvider(
          SimulatedGpsConfig.parse(enabled: true, latitude: '0', longitude: '0'),
        ),
      );

      expect(find.text('Simulated GPS not enabled'), findsOneWidget);
      expect(find.text('Waiting for a valid GPS fix'), findsOneWidget);
      expect(find.byKey(const Key('simulated-gps-badge')), findsNothing);
      expect(harness.mappedItems, isNull);

      await harness.dispose(tester);
    });

    testWidgets('rejected Web Maps key falls back safely with simulation on', (
      tester,
    ) async {
      final harness = await pumpPage(
        tester,
        simulatedLocations: activeProvider(),
        runtimeResult: const MapsRuntimeResult(
          MapsRuntimeStatus.invalidConfiguration,
          message: 'The Web Maps API key was rejected.',
        ),
      );

      expect(
        find.text('Interactive map unavailable in development mode.'),
        findsOneWidget,
      );
      expect(find.text('The Web Maps API key was rejected.'), findsOneWidget);
      expect(find.byKey(const Key('schematic-map-preview')), findsOneWidget);
      expect(harness.mappedItems, isNull, reason: 'Google Map not constructed');
      expect(find.textContaining('Demo location 31.5204'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await harness.dispose(tester);
    });

    testWidgets('a timed-out map script falls back safely', (tester) async {
      final harness = await pumpPage(
        tester,
        runtimeResult: const MapsRuntimeResult(
          MapsRuntimeStatus.timedOut,
          message:
              'The Google Maps JavaScript API did not become ready in time.',
        ),
      );

      expect(
        find.text('The Google Maps JavaScript API did not become ready in time.'),
        findsOneWidget,
      );
      expect(harness.mappedItems, isNull);
      expect(tester.takeException(), isNull);

      await harness.dispose(tester);
    });
  });
}

// Any helmet will do: the provider does not read helmet fields.
Helmet _helmet(String _) => MockDataSet.currentDemo(
  referenceTimeUtc: DateTime.utc(2026, 8, 3, 12),
).helmets['H-03']!;

Future<void> _settleStreams() async {
  for (var index = 0; index < 5; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _ImmediateMapsRuntime implements MapsRuntime {
  const _ImmediateMapsRuntime(this.result);
  final MapsRuntimeResult result;

  @override
  Future<MapsRuntimeResult> initialize() async => result;
}

final class _PageHarness {
  _PageHarness(this.fixture, this.dashboard, this.focus);

  final _Fixture fixture;
  final DashboardViewModel dashboard;
  final MapFocusController focus;
  List<HelmetMapItem>? mappedItems;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    dashboard.dispose();
    fixture.dispose();
  }
}

final class _Fixture {
  _Fixture(
    this.now, {
    String? removeLocationOf,
    SimulatedLocationProvider simulatedLocations =
        const DisabledSimulatedLocationProvider(),
  }) : data = MockDataSet.currentDemo(referenceTimeUtc: now) {
    if (removeLocationOf != null) {
      // Same shape as helmet001 today: telemetry present, no GPS module.
      final json = data.readings[removeLocationOf]!.toJson()
        ..remove('location')
        ..['gpsStatus'] = GpsStatus.invalid.name;
      data.readings[removeLocationOf] = SensorReading.fromJson(json);
    }
    authentication = MockAuthenticationRepository(data);
    users = MockUserRepository(data);
    dependencies = AppDependencies(
      authentication: authentication,
      users: users,
      sites: MockSiteRepository(data),
      helmets: MockHelmetRepository(data),
      readings: MockReadingRepository(data),
      alerts: MockAlertRepository(data),
      configuration: MockConfigurationRepository(data),
      dataSourceKind: DataSourceKind.deterministicMock,
      simulatedLocations: simulatedLocations,
    );
  }

  final MockDataSet data;
  final DateTime now;
  late final MockAuthenticationRepository authentication;
  late final MockUserRepository users;
  late final AppDependencies dependencies;

  DashboardViewModel dashboard(String uid) => DashboardViewModel(
    profile: data.users[uid]!,
    dependencies: dependencies,
    clock: () => now,
    freshnessTick: const Duration(hours: 1),
  )..start();

  void dispose() {
    authentication.dispose();
    users.dispose();
  }
}
