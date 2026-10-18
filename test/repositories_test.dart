import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/domain/repositories.dart';
import 'package:smart_safety/user_role.dart';

void main() {
  late MockDataSet data;
  late MockHelmetRepository helmets;
  late MockReadingRepository readings;
  late MockAlertRepository alerts;
  late MockConfigurationRepository configurations;

  setUp(() {
    data = MockDataSet.currentDemo(
      referenceTimeUtc: DateTime.utc(2026, 8, 2, 12),
    );
    helmets = MockHelmetRepository(data);
    readings = MockReadingRepository(data);
    alerts = MockAlertRepository(
      data,
      clock: () => DateTime.utc(2026, 8, 2, 12, 1),
    );
    configurations = MockConfigurationRepository(data);
  });

  tearDown(() => alerts.dispose());

  test(
    'worker repositories expose only the assigned helmet and its data',
    () async {
      final worker = data.users['worker-ali']!;
      final visibleHelmets = await helmets.watchAuthorizedHelmets(worker).first;
      final latest = await readings.watchLatestReadings(worker).first;
      final visibleAlerts = await alerts.watchAuthorizedAlerts(worker).first;

      expect(visibleHelmets.map((item) => item.helmetId), ['H-03']);
      expect(latest.keys, {'H-03'});
      expect(visibleAlerts, isNotEmpty);
      expect(visibleAlerts.every((alert) => alert.helmetId == 'H-03'), isTrue);
    },
  );

  test(
    'view lifecycle is backend-shaped and worker remains in own scope',
    () async {
      final worker = data.users['worker-ali']!;
      final viewed = await alerts.markViewed(
        actor: worker,
        alertId: 'alert-humidity-h03',
      );

      expect(viewed.status, AlertStatus.viewed);
      expect(viewed.viewedBy, worker.uid);
      expect(await alerts.getAuthorizedAlert(worker, 'alert-gas-h11'), isNull);
    },
  );

  test(
    'two supervisor acknowledgements preserve the first actor and evidence',
    () async {
      final firstSupervisor = data.users['supervisor-demo']!;
      final secondSupervisor = UserProfile(
        uid: 'supervisor-second',
        displayName: 'Second Supervisor',
        email: 'second@example.test',
        role: UserRole.supervisor,
        active: true,
        siteIds: const ['site-main'],
        authorizedHelmetIds: const ['H-11'],
        updatedAt: DateTime.utc(2026, 8, 2),
      );
      final originalEvidence = Map<String, double?>.from(
        data.alerts['alert-gas-h11']!.evidence,
      );

      final results = await Future.wait([
        alerts.acknowledge(actor: firstSupervisor, alertId: 'alert-gas-h11'),
        alerts.acknowledge(actor: secondSupervisor, alertId: 'alert-gas-h11'),
      ]);

      expect(results[0].acknowledgedBy, firstSupervisor.uid);
      expect(results[1].acknowledgedBy, firstSupervisor.uid);
      expect(results[1].evidence, originalEvidence);
    },
  );

  test(
    'worker cannot acknowledge alerts or update safety configuration',
    () async {
      final worker = data.users['worker-ali']!;

      await expectLater(
        alerts.acknowledge(actor: worker, alertId: 'alert-humidity-h03'),
        throwsA(isA<RepositoryAccessException>()),
      );
      await expectLater(
        configurations.updateConfiguration(
          actor: worker,
          configuration: data.configurations['H-03']!,
        ),
        throwsA(isA<RepositoryAccessException>()),
      );
    },
  );

  test(
    'supervisor acknowledgement is idempotent and preserves evidence',
    () async {
      final supervisor = data.users['supervisor-demo']!;
      final original = data.alerts['alert-gas-h11']!;

      final first = await alerts.acknowledge(
        actor: supervisor,
        alertId: original.alertId,
      );
      final second = await alerts.acknowledge(
        actor: supervisor,
        alertId: original.alertId,
      );

      expect(first.status, AlertStatus.acknowledged);
      expect(second.acknowledgedAt, first.acknowledgedAt);
      expect(second.sensorValue, original.sensorValue);
      expect(second.threshold, original.threshold);
      expect(second.eventId, original.eventId);
    },
  );

  test('unassessed telemetry cannot resolve an existing hazard', () async {
    final supervisor = data.users['supervisor-demo']!;
    await alerts.acknowledge(actor: supervisor, alertId: 'alert-gas-h11');
    final source = data.readings['H-11']!;
    data.readings['H-11'] = SensorReading(
      eventId: 'unassessed-h11',
      helmetId: source.helmetId,
      deviceTimestamp: DateTime.utc(2026, 8, 2, 12, 0, 59),
      serverReceivedAt: DateTime.utc(2026, 8, 2, 12, 0, 59),
      temperatureC: source.temperatureC,
      humidityPct: source.humidityPct,
      gasWarmUp: true,
      fallStatus: FallStatus.notEvaluated,
      sensorFaults: const [
        SensorFault.mq7Uncalibrated,
        SensorFault.mq7HeaterStateUnknown,
      ],
      gpsStatus: GpsStatus.invalid,
      connectivity: ConnectivityStatus.online,
      firmwareVersion: source.firmwareVersion,
      severity: SafetySeverity.unassessed,
    );

    await expectLater(
      alerts.resolve(
        actor: supervisor,
        alertId: 'alert-gas-h11',
        resolutionNote: 'Must not resolve from unassessed telemetry.',
      ),
      throwsA(
        isA<RepositoryAccessException>().having(
          (error) => error.code,
          'code',
          'HAZARD_ONGOING',
        ),
      ),
    );
  });

  test('public user repository rejects creation of trusted roles', () async {
    final users = MockUserRepository(data);
    final supervisor = UserProfile(
      uid: 'self-assigned-supervisor',
      displayName: 'Unsafe User',
      email: 'unsafe@example.test',
      role: UserRole.supervisor,
      active: true,
      updatedAt: DateTime.utc(2026),
    );

    await expectLater(
      users.createWorkerProfile(supervisor),
      throwsA(isA<RepositoryAccessException>()),
    );
    users.dispose();
  });
}
