import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/application/dashboard_view_model.dart';
import 'package:smart_safety/data/firebase_realtime_repositories.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/domain/repositories.dart';

void main() {
  test('approved Realtime Database paths never target the database root', () {
    expect(RealtimeDatabasePaths.user('uid-1'), 'users/uid-1');
    expect(RealtimeDatabasePaths.site('site-1'), 'sites/site-1');
    expect(
      RealtimeDatabasePaths.helmetMeta('helmet-1'),
      'helmets/helmet-1/meta',
    );
    expect(
      RealtimeDatabasePaths.helmetCurrent('helmet-1'),
      'helmets/helmet-1/current',
    );
    expect(
      RealtimeDatabasePaths.helmetReadings('helmet-1'),
      'readings/helmet-1',
    );
    expect(RealtimeDatabasePaths.alerts, 'alerts');
    expect(RealtimeDatabasePaths.configDefaults, 'config/defaults');
    expect(
      RealtimeDatabasePaths.helmetConfig('helmet-1'),
      'config/helmets/helmet-1',
    );
    expect([
      RealtimeDatabasePaths.user('uid-1'),
      RealtimeDatabasePaths.site('site-1'),
      RealtimeDatabasePaths.helmetMeta('helmet-1'),
      RealtimeDatabasePaths.helmetCurrent('helmet-1'),
      RealtimeDatabasePaths.helmetReadings('helmet-1'),
      RealtimeDatabasePaths.alerts,
      RealtimeDatabasePaths.configDefaults,
    ], everyElement(isNot(anyOf('', '/'))));
  });

  test('RTDB keyed assignment projections parse as immutable ID lists', () {
    final profile = UserProfile.fromJson({
      'schemaVersion': '1.0',
      'uid': 'supervisor-1',
      'name': 'Supervisor',
      'email': 'supervisor@example.test',
      'role': 'supervisor',
      'active': true,
      'siteIds': {'site-b': true, 'ignored': false, 'site-a': true},
      'authorizedHelmetIds': {'helmet-b': true, 'helmet-a': true},
      'updatedAt': 1,
    });

    expect(profile.siteIds, ['site-a', 'site-b']);
    expect(profile.authorizedHelmetIds, ['helmet-a', 'helmet-b']);
    expect(() => profile.siteIds.add('site-c'), throwsUnsupportedError);
  });

  group('live monitoring state', () {
    late MockDataSet data;
    late MockAuthenticationRepository authentication;
    late MockUserRepository users;
    late AppDependencies dependencies;

    AppDependencies buildDependencies({bool backendConnected = true}) {
      authentication = MockAuthenticationRepository(data);
      users = MockUserRepository(data);
      return AppDependencies(
        authentication: authentication,
        users: users,
        sites: MockSiteRepository(data),
        helmets: MockHelmetRepository(data),
        readings: MockReadingRepository(
          data,
          backendConnected: backendConnected,
        ),
        alerts: MockAlertRepository(data),
        configuration: MockConfigurationRepository(data),
        dataSourceKind: DataSourceKind.deterministicMock,
      );
    }

    setUp(() {
      data = MockDataSet.currentDemo(
        referenceTimeUtc: DateTime.utc(2026, 8, 3, 12),
      );
      dependencies = buildDependencies();
    });

    tearDown(() {
      authentication.dispose();
      users.dispose();
    });

    test(
      'fresh, stale, warming-up, sensor-fault, and offline are deterministic',
      () async {
        final supervisor = data.users['supervisor-demo']!;
        final viewModel = DashboardViewModel(
          profile: supervisor,
          dependencies: dependencies,
          clock: () => DateTime.utc(2026, 8, 3, 12, 0, 10),
          freshnessTick: const Duration(hours: 1),
        )..start();
        await _settleStreams();

        expect(
          viewModel.monitoringStateFor(data.helmets['H-03']!),
          MonitoringState.safe,
        );

        final staleViewModel = DashboardViewModel(
          profile: supervisor,
          dependencies: dependencies,
          clock: () => DateTime.utc(2026, 8, 3, 12, 1),
          freshnessTick: const Duration(hours: 1),
        )..start();
        await _settleStreams();
        expect(
          staleViewModel.monitoringStateFor(data.helmets['H-03']!),
          MonitoringState.stale,
        );

        final source = data.readings['H-03']!;
        data.readings['H-03'] = _readingLike(
          source,
          gasWarmUp: true,
          gasPpm: null,
          severity: SafetySeverity.unassessed,
        );
        final warmingViewModel = DashboardViewModel(
          profile: supervisor,
          dependencies: dependencies,
          clock: () => DateTime.utc(2026, 8, 3, 12, 0, 10),
          freshnessTick: const Duration(hours: 1),
        )..start();
        await _settleStreams();
        expect(
          warmingViewModel.monitoringStateFor(data.helmets['H-03']!),
          MonitoringState.warmingUp,
        );

        data.readings['H-03'] = _readingLike(
          source,
          severity: SafetySeverity.unassessed,
        );
        final unassessedViewModel = DashboardViewModel(
          profile: supervisor,
          dependencies: dependencies,
          clock: () => DateTime.utc(2026, 8, 3, 12, 0, 10),
          freshnessTick: const Duration(hours: 1),
        )..start();
        await _settleStreams();
        expect(
          unassessedViewModel.monitoringStateFor(data.helmets['H-03']!),
          MonitoringState.sensorFault,
        );
        expect(
          unassessedViewModel.monitoringStateFor(data.helmets['H-03']!),
          isNot(MonitoringState.safe),
        );

        data.readings['H-03'] = _readingLike(
          source,
          temperatureC: null,
          humidityPct: null,
          gasPpm: null,
        );
        final faultViewModel = DashboardViewModel(
          profile: supervisor,
          dependencies: dependencies,
          clock: () => DateTime.utc(2026, 8, 3, 12, 0, 10),
          freshnessTick: const Duration(hours: 1),
        )..start();
        await _settleStreams();
        expect(
          faultViewModel.monitoringStateFor(data.helmets['H-03']!),
          MonitoringState.sensorFault,
        );
        expect(
          viewModel.monitoringStateFor(data.helmets['H-09']!),
          MonitoringState.offline,
        );

        viewModel.dispose();
        staleViewModel.dispose();
        warmingViewModel.dispose();
        unassessedViewModel.dispose();
        faultViewModel.dispose();
      },
    );

    test(
      'backend disconnect immediately prevents a live presentation',
      () async {
        authentication.dispose();
        users.dispose();
        dependencies = buildDependencies(backendConnected: false);
        final viewModel = DashboardViewModel(
          profile: data.users['worker-ali']!,
          dependencies: dependencies,
          clock: () => DateTime.utc(2026, 8, 3, 12, 0, 10),
          freshnessTick: const Duration(hours: 1),
        )..start();
        await _settleStreams();

        expect(
          viewModel.monitoringStateFor(data.helmets['H-03']!),
          MonitoringState.stale,
        );
        expect(viewModel.statisticsAreLive, isFalse);
        viewModel.dispose();
      },
    );
  });

  test('clearing sensitive state cancels every monitoring listener', () async {
    final data = MockDataSet.currentDemo();
    final sites = StreamController<List<Site>>.broadcast();
    final helmets = StreamController<List<Helmet>>.broadcast();
    final readings = StreamController<Map<String, SensorReading>>.broadcast();
    final alerts = StreamController<List<SafetyAlert>>.broadcast();
    final connection = StreamController<bool>.broadcast();
    final authentication = MockAuthenticationRepository(data);
    final users = MockUserRepository(data);
    final dependencies = AppDependencies(
      authentication: authentication,
      users: users,
      sites: _SiteStreams(sites),
      helmets: _HelmetStreams(helmets),
      readings: _ReadingStreams(readings, connection),
      alerts: _AlertStreams(alerts),
      configuration: MockConfigurationRepository(data),
      dataSourceKind: DataSourceKind.liveFirebase,
    );
    final viewModel = DashboardViewModel(
      profile: data.users['supervisor-demo']!,
      dependencies: dependencies,
      freshnessTick: const Duration(hours: 1),
    )..start();
    await _settleStreams();

    expect(sites.hasListener, isTrue);
    expect(helmets.hasListener, isTrue);
    expect(readings.hasListener, isTrue);
    expect(alerts.hasListener, isTrue);
    expect(connection.hasListener, isTrue);

    await viewModel.clearSensitiveState();

    expect(sites.hasListener, isFalse);
    expect(helmets.hasListener, isFalse);
    expect(readings.hasListener, isFalse);
    expect(alerts.hasListener, isFalse);
    expect(connection.hasListener, isFalse);
    viewModel.dispose();
    authentication.dispose();
    users.dispose();
    await sites.close();
    await helmets.close();
    await readings.close();
    await alerts.close();
    await connection.close();
  });
}

Future<void> _settleStreams() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

SensorReading _readingLike(
  SensorReading source, {
  bool gasWarmUp = false,
  Object? temperatureC = _unchanged,
  Object? humidityPct = _unchanged,
  Object? gasPpm = _unchanged,
  SafetySeverity? severity,
}) => SensorReading(
  eventId: source.eventId,
  helmetId: source.helmetId,
  deviceTimestamp: source.deviceTimestamp,
  serverReceivedAt: source.serverReceivedAt,
  temperatureC: identical(temperatureC, _unchanged)
      ? source.temperatureC
      : temperatureC as double?,
  humidityPct: identical(humidityPct, _unchanged)
      ? source.humidityPct
      : humidityPct as double?,
  gasPpm: identical(gasPpm, _unchanged) ? source.gasPpm : gasPpm as double?,
  gasWarmUp: gasWarmUp,
  accelXG: source.accelXG,
  accelYG: source.accelYG,
  accelZG: source.accelZG,
  location: source.location,
  gpsStatus: source.gpsStatus,
  batteryPct: source.batteryPct,
  connectivity: source.connectivity,
  firmwareVersion: source.firmwareVersion,
  severity: severity ?? source.severity,
);

const Object _unchanged = Object();

final class _SiteStreams implements SiteRepository {
  _SiteStreams(this.controller);
  final StreamController<List<Site>> controller;
  @override
  Stream<List<Site>> watchAuthorizedSites(UserProfile actor) =>
      controller.stream;
}

final class _HelmetStreams implements HelmetRepository {
  _HelmetStreams(this.controller);
  final StreamController<List<Helmet>> controller;
  @override
  Future<Helmet?> getAuthorizedHelmet(
    UserProfile actor,
    String helmetId,
  ) async => null;
  @override
  Stream<List<Helmet>> watchAuthorizedHelmets(UserProfile actor) =>
      controller.stream;
}

final class _ReadingStreams implements ReadingRepository {
  _ReadingStreams(this.controller, this.connection);
  final StreamController<Map<String, SensorReading>> controller;
  final StreamController<bool> connection;
  @override
  Stream<bool> watchBackendConnection() => connection.stream;
  @override
  Stream<List<SensorReading>> watchHelmetReadings(
    UserProfile actor,
    String helmetId,
  ) => const Stream.empty();
  @override
  Stream<Map<String, SensorReading>> watchLatestReadings(UserProfile actor) =>
      controller.stream;
}

final class _AlertStreams implements AlertRepository {
  _AlertStreams(this.controller);
  final StreamController<List<SafetyAlert>> controller;
  @override
  Future<SafetyAlert> acknowledge({
    required UserProfile actor,
    required String alertId,
  }) => throw UnimplementedError();
  @override
  Future<SafetyAlert?> getAuthorizedAlert(UserProfile actor, String alertId) =>
      throw UnimplementedError();
  @override
  Future<SafetyAlert> markViewed({
    required UserProfile actor,
    required String alertId,
  }) => throw UnimplementedError();
  @override
  Future<SafetyAlert> resolve({
    required UserProfile actor,
    required String alertId,
    required String resolutionNote,
  }) => throw UnimplementedError();
  @override
  Future<SafetyAlert> retryDelivery({
    required UserProfile actor,
    required String alertId,
  }) => throw UnimplementedError();
  @override
  Stream<SafetyAlert?> watchAuthorizedAlert(
    UserProfile actor,
    String alertId,
  ) => const Stream.empty();
  @override
  Stream<List<SafetyAlert>> watchAuthorizedAlerts(UserProfile actor) =>
      controller.stream;
}
