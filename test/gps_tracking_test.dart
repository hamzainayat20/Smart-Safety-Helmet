import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/application/dashboard_view_model.dart';
import 'package:smart_safety/application/gps_map_view_model.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/domain/repositories.dart';
import 'package:smart_safety/gps_map_page.dart';
import 'package:smart_safety/presentation/formatters.dart';

void main() {
  final now = DateTime.utc(2026, 8, 3, 12);

  test('worker phone location status distinguishes live, stale, and off', () {
    final live = WorkerLocation(
      latitudeDegrees: 31.5204,
      longitudeDegrees: 74.3587,
      accuracyM: 8,
      updatedAt: now.subtract(const Duration(seconds: 37)),
      source: 'phoneGps',
    );
    expect(
      formatWorkerLocationStatus(live, now: now),
      'Sharing location · updated 37s ago',
    );
    final stale = WorkerLocation(
      latitudeDegrees: live.latitudeDegrees,
      longitudeDegrees: live.longitudeDegrees,
      accuracyM: live.accuracyM,
      updatedAt: now.subtract(const Duration(minutes: 2, seconds: 1)),
      source: 'phoneGps',
    );
    expect(formatWorkerLocationStatus(stale, now: now), 'Location may be stale');
    expect(formatWorkerLocationStatus(null, now: now), 'Location off');
  });

  test('invalid 0,0 coordinates are discarded without losing telemetry', () {
    final reading = SensorReading.fromJson({
      'schemaVersion': '1.0',
      'eventId': 'event-invalid-gps',
      'helmetId': 'H-03',
      'deviceTimestamp': now.millisecondsSinceEpoch,
      'serverReceivedAt': now.millisecondsSinceEpoch,
      'temperatureC': 36.5,
      'humidityPct': 50,
      'gasPpm': 100,
      'gasWarmUp': false,
      'location': {
        'latitude': 0,
        'longitude': 0,
        'hdop': 1,
        'capturedAt': now.millisecondsSinceEpoch,
        'isLastKnown': false,
      },
      'gpsStatus': 'valid',
      'batteryPct': 80,
      'connectivity': 'online',
      'firmwareVersion': '1.0.0',
      'severity': 'safe',
    });

    expect(reading.location, isNull);
    expect(reading.gpsStatus, GpsStatus.invalid);
    expect(reading.temperatureC, 36.5);
  });

  test(
    'missing GPS produces acquiring state and no geographic marker',
    () async {
      final fixture = _Fixture(now);
      final source = fixture.data.readings['H-03']!;
      fixture.data.readings['H-03'] = _copyReading(
        source,
        location: null,
        gpsStatus: GpsStatus.acquiring,
      );
      final dashboard = fixture.dashboard('worker-ali');
      await _settleStreams();
      final map = GpsMapViewModel(dashboard: dashboard, clock: () => now);

      expect(map.items, hasLength(1));
      expect(map.items.single.markerState, HelmetMapState.gpsAcquiring);
      expect(map.positionedItems, isEmpty);
      expect(map.unpositionedItems.single.helmet.helmetId, 'H-03');

      map.dispose();
      dashboard.dispose();
      fixture.dispose();
    },
  );

  test('GPS fixes older than two minutes are marked stale', () async {
    final fixture = _Fixture(now);
    final source = fixture.data.readings['H-03']!;
    fixture.data.readings['H-03'] = _copyReading(
      source,
      serverReceivedAt: now.subtract(const Duration(seconds: 5)),
      location: GPSLocation(
        latitudeDegrees: 31.4629,
        longitudeDegrees: 74.3181,
        hdop: 1.1,
        capturedAt: now.subtract(const Duration(minutes: 2, seconds: 1)),
        isLastKnown: false,
      ),
      gpsStatus: GpsStatus.valid,
    );
    final dashboard = fixture.dashboard('worker-ali');
    await _settleStreams();
    final map = GpsMapViewModel(dashboard: dashboard, clock: () => now);

    expect(map.items.single.markerState, HelmetMapState.stale);
    expect(map.positionedItems, hasLength(1));

    map.dispose();
    dashboard.dispose();
    fixture.dispose();
  });

  test('worker map projection cannot expose unauthorized helmets', () async {
    final fixture = _Fixture(now);
    final dashboard = fixture.dashboard('worker-ali');
    await _settleStreams();
    final map = GpsMapViewModel(dashboard: dashboard, clock: () => now);

    expect(map.items.map((item) => item.helmet.helmetId), ['H-03']);
    expect(
      map.items.every((item) => item.helmet.assignedWorkerId == 'worker-ali'),
      isTrue,
    );

    map.dispose();
    dashboard.dispose();
    fixture.dispose();
  });

  test('worker selection creates a platform-neutral focus request', () async {
    final fixture = _Fixture(now);
    final dashboard = fixture.dashboard('worker-ali');
    await _settleStreams();
    final map = GpsMapViewModel(dashboard: dashboard, clock: () => now);
    final request = map.focusForWorker('H-03');

    expect(request, isNotNull);
    expect(request!.helmetId, 'H-03');
    expect(request.reason, MapFocusReason.workerSelection);
    expect(request.location, same(map.items.single.location));
    expect(request.zoom, 16);

    map.dispose();
    dashboard.dispose();
    fixture.dispose();
  });

  test('critical notification creates authorized incident camera focus', () {
    final fixture = _Fixture(now);
    final alert = fixture.data.alerts['alert-gas-h11']!;
    final request = criticalNotificationMapFocus(
      actor: fixture.data.users['supervisor-demo']!,
      alert: alert,
    );

    expect(request, isNotNull);
    expect(request!.alertId, alert.alertId);
    expect(request.helmetId, alert.helmetId);
    expect(request.reason, MapFocusReason.criticalIncident);
    expect(request.location, same(alert.location));
    expect(request.zoom, 17);
    expect(
      criticalNotificationMapFocus(
        actor: fixture.data.users['worker-ali']!,
        alert: alert,
      ),
      isNull,
    );

    fixture.dispose();
  });

  testWidgets('permission denial is shown without constructing Google Map', (
    tester,
  ) async {
    final fixture = _Fixture(now, helmets: const _DeniedHelmetRepository());
    final dashboard = fixture.dashboard('supervisor-demo');
    final focus = MapFocusController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF07152C),
          body: GpsMapPage(
            viewModel: dashboard,
            onSignOut: () {},
            focusController: focus,
            mapBuilder: (_, _, _, _, _) =>
                throw StateError('Google Map must not be constructed'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Location access denied'), findsOneWidget);
    expect(
      find.text(
        'Worker locations are unavailable for this account or assignment.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    dashboard.dispose();
    fixture.dispose();
  });
}

final class _Fixture {
  _Fixture(this.now, {HelmetRepository? helmets})
    : data = MockDataSet.currentDemo(referenceTimeUtc: now) {
    authentication = MockAuthenticationRepository(data);
    users = MockUserRepository(data);
    dependencies = AppDependencies(
      authentication: authentication,
      users: users,
      sites: MockSiteRepository(data),
      helmets: helmets ?? MockHelmetRepository(data),
      readings: MockReadingRepository(data),
      alerts: MockAlertRepository(data),
      configuration: MockConfigurationRepository(data),
      dataSourceKind: DataSourceKind.deterministicMock,
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

final class _DeniedHelmetRepository implements HelmetRepository {
  const _DeniedHelmetRepository();

  @override
  Future<Helmet?> getAuthorizedHelmet(UserProfile actor, String helmetId) =>
      throw const RepositoryAccessException(
        'PERMISSION_DENIED',
        'Worker locations are outside the assigned scope.',
      );

  @override
  Stream<List<Helmet>> watchAuthorizedHelmets(UserProfile actor) =>
      Stream.error(
        const RepositoryAccessException(
          'PERMISSION_DENIED',
          'Worker locations are outside the assigned scope.',
        ),
      );
}

Future<void> _settleStreams() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

const Object _unchanged = Object();

SensorReading _copyReading(
  SensorReading source, {
  Object? location = _unchanged,
  GpsStatus? gpsStatus,
  DateTime? serverReceivedAt,
}) => SensorReading(
  eventId: source.eventId,
  helmetId: source.helmetId,
  deviceTimestamp: source.deviceTimestamp,
  serverReceivedAt: serverReceivedAt ?? source.serverReceivedAt,
  temperatureC: source.temperatureC,
  humidityPct: source.humidityPct,
  gasPpm: source.gasPpm,
  gasWarmUp: source.gasWarmUp,
  accelXG: source.accelXG,
  accelYG: source.accelYG,
  accelZG: source.accelZG,
  location: identical(location, _unchanged)
      ? source.location
      : location as GPSLocation?,
  gpsStatus: gpsStatus ?? source.gpsStatus,
  batteryPct: source.batteryPct,
  connectivity: source.connectivity,
  firmwareVersion: source.firmwareVersion,
  severity: source.severity,
);
