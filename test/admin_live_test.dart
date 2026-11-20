import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/admin_repository.dart';
import 'package:smart_safety/data/mock_admin_repository.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/presentation/admin/admin_live_screen.dart';
import 'package:smart_safety/presentation/design_system/design_system.dart';

void main() {
  final reference = DateTime.utc(2026, 11, 20, 12);
  late MockDataSet data;

  setUp(() => data = MockDataSet.currentDemo(referenceTimeUtc: reference));

  AdminLiveHelmet live(
    String helmetId, {
    bool withReading = true,
    bool unreadable = false,
    String provisioningStatus = 'provisioned',
  }) => AdminLiveHelmet(
    meta: HelmetMetaRecord(
      helmetId: helmetId,
      provisioningStatus: provisioningStatus,
    ),
    current: withReading ? data.readings[helmetId] : null,
    telemetryUnreadable: unreadable,
  );

  group('adminLiveStateFor', () {
    test('a fresh safe reading is Safe', () {
      final state = adminLiveStateFor(live('H-02'), now: reference);
      expect(state.status, SafetyStatus.normal);
      expect(state.label, 'Safe');
    });

    test('a fresh critical reading is Critical and sorts first', () {
      final critical = adminLiveStateFor(live('H-11'), now: reference);
      final safe = adminLiveStateFor(live('H-02'), now: reference);
      expect(critical.status, SafetyStatus.critical);
      expect(critical.rank, lessThan(safe.rank));
    });

    test('an old reading becomes stale, then offline — never safe', () {
      final stale = adminLiveStateFor(
        live('H-02'),
        now: reference.add(const Duration(minutes: 1)),
      );
      expect(stale.status, SafetyStatus.stale);
      final offline = adminLiveStateFor(
        live('H-02'),
        now: reference.add(const Duration(minutes: 10)),
      );
      expect(offline.status, SafetyStatus.offline);
    });

    test('a lost database connection is never shown as safe', () {
      final state = adminLiveStateFor(
        live('H-02'),
        now: reference,
        connected: false,
      );
      expect(state.status, SafetyStatus.stale);
      expect(state.label, 'Connection lost');
    });

    test('missing, unreadable and retired helmets are unknown', () {
      expect(
        adminLiveStateFor(live('H-02', withReading: false), now: reference)
            .label,
        'No data yet',
      );
      expect(
        adminLiveStateFor(live('H-02', unreadable: true), now: reference)
            .label,
        'Unreadable data',
      );
      expect(
        adminLiveStateFor(
          live('H-02', provisioningStatus: 'revoked'),
          now: reference,
        ).label,
        'Retired',
      );
    });
  });

  test('formatLiveAge reports seconds while data is fresh', () {
    expect(formatLiveAge(reference, reference), 'now');
    expect(
      formatLiveAge(reference, reference.add(const Duration(seconds: 12))),
      '12s ago',
    );
    expect(
      formatLiveAge(reference, reference.add(const Duration(minutes: 4))),
      '4m ago',
    );
  });

  test('demo repository joins helmet records with live readings', () async {
    final repository = MockAdminRepository(data);
    final fleet = await repository.watchLiveFleet().first;
    final h11 = fleet.singleWhere((helmet) => helmet.helmetId == 'H-11');
    expect(h11.current, isNotNull);
    expect(h11.current!.helmetId, 'H-11');

    final alerts = await repository.watchRecentAlerts(limit: 2).first;
    expect(alerts.length, lessThanOrEqualTo(2));
    for (var i = 1; i < alerts.length; i++) {
      expect(
        alerts[i - 1].serverReceivedAt.isBefore(alerts[i].serverReceivedAt),
        isFalse,
      );
    }
    expect(await repository.watchBackendConnection().first, isTrue);
  });

  test('the Noop repository serves no live data and reports offline', () async {
    const repository = NoopAdminRepository();
    expect(await repository.watchLiveFleet().first, isEmpty);
    expect(await repository.watchRecentAlerts().first, isEmpty);
    expect(await repository.watchBackendConnection().first, isFalse);
  });

  testWidgets('live screen renders helmet cards and live values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repository = MockAdminRepository(data);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AdminLiveScreen(
            admin: repository,
            onSignOut: () {},
            clock: () => reference,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Live monitor'), findsOneWidget);
    expect(find.text('Reporting now'), findsOneWidget);
    expect(find.text('H-11'), findsOneWidget);
    expect(find.text('Critical'), findsWidgets);
    expect(find.textContaining('°C'), findsWidgets);

    // Dispose the screen so its once-a-second ticker is cancelled.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
