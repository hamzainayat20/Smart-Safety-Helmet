import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/alert_detail_screen.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/application/dashboard_view_model.dart';
import 'package:smart_safety/application/session_controller.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/domain/repositories.dart';
import 'package:smart_safety/login_screen.dart';
import 'package:smart_safety/main.dart';
import 'package:smart_safety/sensor_detail_screen.dart';
import 'package:smart_safety/user_role.dart';

void main() {
  testWidgets('supervisor dashboard renders repository-backed demo snapshot', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dependencies = AppDependencies.allMocks(
      initialUid: 'supervisor-demo',
      referenceTimeUtc: DateTime.now().toUtc(),
    );

    await tester.pumpWidget(
      MyApp(dependencies: dependencies, splashDuration: Duration.zero),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Demo data'), findsWidgets);
    expect(find.text('Act now'), findsOneWidget);
    expect(find.text('12/14'), findsNothing);

    // The redesigned dashboard keeps worker status below the urgent summary.
    // Scroll the lazy list before asserting content that starts off-screen.
    await tester.scrollUntilVisible(
      find.text('Worker Status'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Worker Status'), findsOneWidget);
    expect(find.text('Zain Ahmed'), findsOneWidget);
  });

  testWidgets('worker dashboard reads assigned helmet from repositories', (
    tester,
  ) async {
    final dependencies = AppDependencies.allMocks(
      initialUid: 'worker-ali',
      referenceTimeUtc: DateTime.now().toUtc(),
    );

    await tester.pumpWidget(
      MyApp(dependencies: dependencies, splashDuration: Duration.zero),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Status: SAFE'), findsOneWidget);
    expect(find.textContaining('Your Helmet Status • H-03'), findsOneWidget);
    expect(find.text('87 %'), findsOneWidget);
  });

  testWidgets('worker can open the assistant and receive a demo explanation', (
    tester,
  ) async {
    final dependencies = AppDependencies.allMocks(
      initialUid: 'worker-ali',
      referenceTimeUtc: DateTime.now().toUtc(),
    );

    await tester.pumpWidget(
      MyApp(dependencies: dependencies, splashDuration: Duration.zero),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();
    expect(find.text('Safety Assistant'), findsOneWidget);
    expect(find.text('H-03'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Summarize the current safety assessment.',
    );
    await tester.ensureVisible(find.text('Ask assistant'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ask assistant'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Assistant response'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Assistant response'), findsOneWidget);
    expect(
      find.textContaining('current demo assessment is safe'),
      findsOneWidget,
    );
    expect(find.textContaining('Demo decision-support'), findsOneWidget);
  });

  testWidgets('disconnected backend marks cached worker values stale', (
    tester,
  ) async {
    final dependencies = AppDependencies.allMocks(
      initialUid: 'worker-ali',
      referenceTimeUtc: DateTime.now().toUtc(),
      backendConnected: false,
    );

    await tester.pumpWidget(
      MyApp(dependencies: dependencies, splashDuration: Duration.zero),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Status: STALE'), findsOneWidget);
    expect(
      find.textContaining(
        'Values are last known and are not being presented as live',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Last update'), findsOneWidget);
  });

  testWidgets('supervisor login does not offer public trusted-role signup', (
    tester,
  ) async {
    final dependencies = AppDependencies.allMocks();
    final session = SessionController(dependencies)..start();

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(role: UserRole.supervisor, session: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Supervisor accounts are invite-only'), findsOneWidget);
    expect(find.text('Create worker account'), findsNothing);
    session.dispose();
  });

  testWidgets('forgot password reports a generic repository result', (
    tester,
  ) async {
    final dependencies = AppDependencies.allMocks();
    final session = SessionController(dependencies)..start();

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(role: UserRole.worker, session: session),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'unknown@example.test',
    );
    await tester.tap(find.byKey(const Key('forgot-password')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-result')), findsOneWidget);
    expect(find.textContaining('If an account exists'), findsOneWidget);
    session.dispose();
  });

  testWidgets('login does not offer email verification while disabled', (
    tester,
  ) async {
    final dependencies = AppDependencies.allMocks(
      unverifiedUids: const {'supervisor-demo'},
    );
    final session = SessionController(dependencies)..start();

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(role: UserRole.supervisor, session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('resend-verification')), findsNothing);
    expect(find.textContaining('verification email'), findsNothing);
    expect(find.byKey(const Key('forgot-password')), findsOneWidget);
    session.dispose();
  });

  testWidgets('sensor detail uses MQ-7 and never labels invalid GPS current', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final data = MockDataSet.currentDemo(
      referenceTimeUtc: DateTime.now().toUtc(),
    );
    final readingJson = Map<String, dynamic>.from(
      data.readings['H-02']!.toJson(),
    )..['gpsStatus'] = GpsStatus.invalid.name;
    readingJson.remove('location');
    data.readings['H-02'] = SensorReading.fromJson(readingJson);
    final dependencies = AppDependencies(
      authentication: MockAuthenticationRepository(data),
      users: MockUserRepository(data),
      sites: MockSiteRepository(data),
      helmets: MockHelmetRepository(data),
      readings: MockReadingRepository(data),
      alerts: MockAlertRepository(data),
      configuration: MockConfigurationRepository(data),
      dataSourceKind: DataSourceKind.deterministicMock,
    );
    final viewModel = DashboardViewModel(
      profile: data.users['supervisor-demo']!,
      dependencies: dependencies,
    )..start();

    await tester.pumpWidget(
      MaterialApp(
        home: SensorDetailScreen(
          helmetId: 'H-02',
          workerName: 'Test Worker',
          viewModel: viewModel,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gas Level (MQ-7)'), findsOneWidget);
    expect(find.text('Gas Level (MQ135)'), findsNothing);
    expect(find.text('GPS Status'), findsOneWidget);
    expect(find.text('Current fix'), findsNothing);
    expect(find.text('Unavailable'), findsWidgets);
    viewModel.dispose();
  });

  testWidgets(
    'worker alert status filter changes the visible repository data',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dependencies = AppDependencies.allMocks(
        initialUid: 'worker-ali',
        referenceTimeUtc: DateTime.now().toUtc(),
      );
      await tester.pumpWidget(
        MyApp(dependencies: dependencies, splashDuration: Duration.zero),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Alerts'));
      await tester.pumpAndSettle();

      expect(find.text('High Humidity'), findsOneWidget);
      await tester.tap(find.text('Resolved').last);
      await tester.pumpAndSettle();

      expect(find.text('High Humidity'), findsNothing);
      expect(find.textContaining('Gas Level'), findsOneWidget);
    },
  );

  testWidgets(
    'acknowledgement stays pending until canonical backend response',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = MockDataSet.currentDemo(
        referenceTimeUtc: DateTime.now().toUtc(),
      );
      final base = AppDependencies.allMocks();
      final repository = _DelayedAlertRepository(data.alerts['alert-gas-h11']!);
      final dependencies = AppDependencies(
        authentication: base.authentication,
        users: base.users,
        sites: base.sites,
        helmets: base.helmets,
        readings: base.readings,
        alerts: repository,
        configuration: base.configuration,
        dataSourceKind: DataSourceKind.deterministicMock,
      );
      final supervisor = data.users['supervisor-demo']!;

      await tester.pumpWidget(
        MaterialApp(
          home: AlertDetailScreen(
            profile: supervisor,
            alertId: repository.alert.alertId,
            dependencies: dependencies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('acknowledge-alert-button')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('acknowledge-alert-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Acknowledge'),
        ),
      );
      await tester.pump();

      expect(find.text('Confirming with backend...'), findsOneWidget);
      expect(find.text('Awaiting supervisor acknowledgement'), findsOneWidget);

      repository.confirmAcknowledgement(supervisor.uid);
      await tester.pumpAndSettle();

      expect(find.textContaining('by ${supervisor.uid}'), findsWidgets);
      expect(find.text('Confirming with backend...'), findsNothing);
      repository.dispose();
    },
  );
}

final class _DelayedAlertRepository implements AlertRepository {
  _DelayedAlertRepository(this.alert);

  SafetyAlert alert;
  final StreamController<SafetyAlert?> _controller =
      StreamController.broadcast();
  final Completer<SafetyAlert> _acknowledgement = Completer();

  void confirmAcknowledgement(String uid) {
    alert = alert.acknowledged(actorUid: uid, at: DateTime.now().toUtc());
    _controller.add(alert);
    _acknowledgement.complete(alert);
  }

  @override
  Future<SafetyAlert> acknowledge({
    required UserProfile actor,
    required String alertId,
  }) => _acknowledgement.future;

  @override
  Future<SafetyAlert?> getAuthorizedAlert(
    UserProfile actor,
    String alertId,
  ) async => alert;

  @override
  Future<SafetyAlert> markViewed({
    required UserProfile actor,
    required String alertId,
  }) async {
    alert = alert.viewed(actorUid: actor.uid, at: DateTime.now().toUtc());
    _controller.add(alert);
    return alert;
  }

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
  }) async => alert;

  @override
  Stream<SafetyAlert?> watchAuthorizedAlert(
    UserProfile actor,
    String alertId,
  ) async* {
    yield alert;
    yield* _controller.stream;
  }

  @override
  Stream<List<SafetyAlert>> watchAuthorizedAlerts(UserProfile actor) =>
      Stream.value([alert]);

  void dispose() => _controller.close();
}
