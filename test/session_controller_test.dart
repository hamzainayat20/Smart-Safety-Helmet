import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/application/app_dependencies.dart';
import 'package:smart_safety/application/session_controller.dart';
import 'package:smart_safety/data/mock_repositories.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/domain/repositories.dart';
import 'package:smart_safety/user_role.dart';

void main() {
  late MockDataSet data;
  late MockAuthenticationRepository authentication;
  late MockUserRepository users;
  late AppDependencies dependencies;

  AppDependencies buildDependencies({
    Set<String> unverified = const {},
    Set<String> disabled = const {},
    Set<String> unclaimed = const {},
    bool failProfileCreation = false,
    bool failVerificationEmail = false,
    NotificationRepository notifications = const NoopNotificationRepository(),
  }) {
    authentication = MockAuthenticationRepository(
      data,
      unverifiedUids: unverified,
      disabledUids: disabled,
      unclaimedUids: unclaimed,
      failVerificationEmail: failVerificationEmail,
    );
    users = MockUserRepository(data, failProfileCreation: failProfileCreation);
    return AppDependencies(
      authentication: authentication,
      users: users,
      sites: MockSiteRepository(data),
      helmets: MockHelmetRepository(data),
      readings: MockReadingRepository(data),
      alerts: MockAlertRepository(data),
      configuration: MockConfigurationRepository(data),
      notifications: notifications,
      dataSourceKind: DataSourceKind.deterministicMock,
    );
  }

  setUp(() {
    data = MockDataSet.currentDemo(referenceTimeUtc: DateTime.utc(2026, 8, 2));
    dependencies = buildDependencies();
  });

  tearDown(() {
    authentication.dispose();
    users.dispose();
  });

  test('portal preference cannot grant a different effective role', () async {
    final session = SessionController(dependencies);
    final result = await session.signIn(
      email: 'worker@example.test',
      password: 'password',
      expectedRole: UserRole.supervisor,
    );
    expect(result.succeeded, isFalse);
    expect(result.issue, SessionIssue.roleMismatch);
    expect(session.profile, isNull);
    session.dispose();
  });

  test('privileged profile without a backend claim fails closed', () async {
    dependencies = buildDependencies(unclaimed: {'supervisor-demo'});
    final session = SessionController(dependencies);
    final result = await session.signIn(
      email: 'supervisor@example.test',
      password: 'password',
      expectedRole: UserRole.supervisor,
    );
    expect(result.issue, SessionIssue.untrustedRole);
    session.dispose();
  });

  test(
    'worker may use a protected assignment record without a claim',
    () async {
      dependencies = buildDependencies(unclaimed: {'worker-ali'});
      final session = SessionController(dependencies);
      final result = await session.signIn(
        email: 'worker@example.test',
        password: 'password',
        expectedRole: UserRole.worker,
      );
      expect(result.succeeded, isTrue);
      session.dispose();
    },
  );

  test('disabled Firebase account produces a safe result', () async {
    dependencies = buildDependencies(disabled: {'worker-ali'});
    final session = SessionController(dependencies);
    final result = await session.signIn(
      email: 'worker@example.test',
      password: 'password',
      expectedRole: UserRole.worker,
    );
    expect(result.issue, SessionIssue.disabledAccount);
    expect(result.message, contains('disabled'));
    session.dispose();
  });

  test(
    'unverified worker can sign in while verification gate is disabled',
    () async {
      dependencies = buildDependencies(unverified: {'worker-ali'});
      final session = SessionController(dependencies);
      final result = await session.signIn(
        email: 'worker@example.test',
        password: 'password',
        expectedRole: UserRole.worker,
      );
      expect(result.succeeded, isTrue);
      expect(result.issue, SessionIssue.none);
      expect(authentication.verificationEmailCount, 0);
      session.dispose();
    },
  );

  test('password reset uses generic success messaging', () async {
    final session = SessionController(dependencies);
    final result = await session.sendPasswordReset('unknown@example.test');
    expect(result.succeeded, isTrue);
    expect(result.message, contains('If an account exists'));
    expect(authentication.passwordResetRequests, ['unknown@example.test']);
    session.dispose();
  });

  test('failed worker profile creation rolls back new auth user', () async {
    dependencies = buildDependencies(failProfileCreation: true);
    final session = SessionController(dependencies);

    final result = await session.registerWorker(
      email: 'new-worker@example.test',
      password: 'password',
      displayName: 'New Worker',
      organizationName: 'Test Site',
    );

    expect(result.succeeded, isFalse);
    expect(authentication.deletedCurrentUserCount, 1);
    expect(
      data.users.values.any(
        (profile) => profile.email == 'new-worker@example.test',
      ),
      isFalse,
    );
    session.dispose();
  });

  test('worker registration does not request email verification', () async {
    dependencies = buildDependencies(failVerificationEmail: true);
    final session = SessionController(dependencies);

    final result = await session.registerWorker(
      email: 'new-worker@example.test',
      password: 'password',
      displayName: 'New Worker',
      organizationName: 'Test Site',
    );

    expect(result.succeeded, isTrue);
    expect(result.message, 'Worker account created. You can sign in now.');
    expect(authentication.verificationEmailCount, 0);
    expect(authentication.deletedCurrentUserCount, 0);
    expect(
      data.users.values.any(
        (profile) => profile.email == 'new-worker@example.test',
      ),
      isTrue,
    );
    session.dispose();
  });

  test('sign-out invokes registered sensitive-data clearers', () async {
    var clearCount = 0;
    dependencies.sensitiveData.register(() async => clearCount++);
    final session = SessionController(dependencies);
    await session.signOut();
    expect(clearCount, 1);
    session.dispose();
  });

  test(
    'supervisor notification association starts after trust and clears on sign-out',
    () async {
      final notifications = _RecordingNotificationRepository();
      dependencies = buildDependencies(notifications: notifications);
      final session = SessionController(dependencies)..start();
      final result = await session.signIn(
        email: 'supervisor@example.test',
        password: 'password',
        expectedRole: UserRole.supervisor,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result.succeeded, isTrue);
      expect(notifications.activatedUids, ['supervisor-demo']);

      await session.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifications.deactivatedUids, contains('supervisor-demo'));
      session.dispose();
    },
  );

  test('inactive trusted profile is rejected', () async {
    final current = data.users['worker-ali']!;
    data.users['worker-ali'] = UserProfile(
      uid: current.uid,
      displayName: current.displayName,
      email: current.email,
      role: current.role,
      active: false,
      organizationName: current.organizationName,
      siteIds: current.siteIds,
      authorizedHelmetIds: current.authorizedHelmetIds,
      updatedAt: current.updatedAt,
    );
    final session = SessionController(dependencies);
    final result = await session.signIn(
      email: 'worker@example.test',
      password: 'password',
      expectedRole: UserRole.worker,
    );
    expect(result.issue, SessionIssue.inactiveProfile);
    session.dispose();
  });
}

final class _RecordingNotificationRepository implements NotificationRepository {
  final List<String> activatedUids = [];
  final List<String?> deactivatedUids = [];

  @override
  Stream<AlertNotificationIntent> get alertIntents => const Stream.empty();

  @override
  Future<void> activateForSupervisor(UserProfile actor) async {
    activatedUids.add(actor.uid);
  }

  @override
  Future<void> deactivate({UserProfile? actor}) async {
    deactivatedUids.add(actor?.uid);
  }

  @override
  void dispose() {}

  @override
  Future<void> initialize() async {}
}
