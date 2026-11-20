import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_safety/data/admin_repository.dart';
import 'package:smart_safety/domain/models.dart';
import 'package:smart_safety/presentation/admin/admin_audit_screen.dart';
import 'package:smart_safety/presentation/admin/admin_overview.dart';
import 'package:smart_safety/presentation/admin/admin_thresholds_screen.dart';
import 'package:smart_safety/presentation/admin/admin_user_edit_screen.dart';
import 'package:smart_safety/presentation/admin/admin_users_screen.dart';
import 'package:smart_safety/presentation/design_system/design_system.dart';
import 'package:smart_safety/user_role.dart';

UserProfile _user({
  required String uid,
  required String name,
  required String email,
  required UserRole role,
  bool active = true,
}) => UserProfile(
  uid: uid,
  displayName: name,
  email: email,
  role: role,
  active: active,
  updatedAt: DateTime.utc(2026, 1, 1),
);

final _admin = _user(
  uid: 'admin-1',
  name: 'Adam Admin',
  email: 'adam@example.com',
  role: UserRole.administrator,
);

HelmetConfiguration _config(String helmetId) => HelmetConfiguration(
  helmetId: helmetId,
  configVersion: '1.0',
  temperatureWarningC: 35,
  temperatureCriticalC: 40,
  humidityWarningLowPct: 40,
  humidityCriticalLowPct: 30,
  humidityWarningHighPct: 70,
  humidityCriticalHighPct: 85,
  gasWarningPpm: 50,
  gasCriticalPpm: 100,
  fallImpactThresholdG: 2,
  fallDuplicateCooldownSeconds: 30,
  normalPollingIntervalSeconds: 5,
  gasWarmUpHours: 0,
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedBy: 'admin-1',
);

final class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({
    List<UserProfile> users = const [],
    List<HelmetMetaRecord> helmets = const [],
    List<Site> sites = const [],
    Map<String, HelmetConfiguration> thresholds = const {},
    List<AuditLogEntry> audit = const [],
    List<AdminLiveHelmet> live = const [],
    List<SafetyAlert> recentAlerts = const [],
  }) : _users = users,
       _helmets = helmets,
       _sites = sites,
       _thresholds = thresholds,
       _audit = audit,
       _live = live,
       _recentAlerts = recentAlerts;

  final List<AdminLiveHelmet> _live;
  final List<SafetyAlert> _recentAlerts;
  final List<UserProfile> _users;
  final List<HelmetMetaRecord> _helmets;
  final List<Site> _sites;
  final Map<String, HelmetConfiguration> _thresholds;
  final List<AuditLogEntry> _audit;

  int createUserCalls = 0;
  int setThresholdsCalls = 0;
  int passwordResetCalls = 0;

  @override
  bool get isLive => true;

  @override
  Stream<List<UserProfile>> watchUsers() => Stream.value(_users);

  @override
  Stream<List<HelmetMetaRecord>> watchHelmetsMeta() => Stream.value(_helmets);

  @override
  Stream<List<Site>> watchSites() => Stream.value(_sites);

  @override
  Stream<HelmetConfiguration?> watchThresholds(String helmetId) =>
      Stream.value(_thresholds[helmetId]);

  @override
  Stream<List<AuditLogEntry>> watchAuditLog({int limit = 100}) =>
      Stream.value(_audit);

  @override
  Stream<AdminOverview> watchOverview() => Stream.value(
    AdminOverview.from(
      users: _users,
      helmets: _helmets,
      alertsToday: 2,
      criticalUnacknowledged: 1,
    ),
  );

  @override
  Stream<List<AdminLiveHelmet>> watchLiveFleet() => Stream.value(_live);

  @override
  Stream<List<SafetyAlert>> watchRecentAlerts({int limit = 50}) =>
      Stream.value(_recentAlerts);

  @override
  Stream<bool> watchBackendConnection() => Stream.value(true);

  @override
  Future<AdminUserAssignments> getUserAssignments(String uid) async =>
      const AdminUserAssignments();

  @override
  Future<CreatedUserResult> createUser({
    required String email,
    required String name,
    required UserRole role,
    String? organizationName,
    List<String> siteIds = const [],
  }) async {
    createUserCalls++;
    final user = _user(uid: 'new-user', name: name, email: email, role: role);
    return CreatedUserResult(
      uid: user.uid,
      user: user,
      passwordSetupLink: 'https://example.com/setup',
    );
  }

  @override
  Future<UserProfile> setUserRole({
    required String uid,
    required UserRole role,
  }) async => _users.firstWhere((user) => user.uid == uid);

  @override
  Future<UserProfile> setUserActive({
    required String uid,
    required bool active,
  }) async => _users.firstWhere((user) => user.uid == uid);

  @override
  Future<UserProfile> updateUserProfile({
    required String uid,
    String? name,
    String? organizationName,
  }) async => _users.firstWhere((user) => user.uid == uid);

  @override
  Future<UserProfile> updateUserAssignments({
    required String uid,
    List<String>? siteIds,
    List<String>? authorizedHelmetIds,
    List<String>? authorizedSupervisorIds,
  }) async => _users.firstWhere((user) => user.uid == uid);

  @override
  Future<void> deleteUser({required String uid}) async {}

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetCalls++;
  }

  @override
  Future<RegisteredHelmetResult> registerHelmet({
    required String helmetId,
    String? siteId,
    String? label,
  }) async => RegisteredHelmetResult(
    helmet: HelmetMetaRecord(helmetId: helmetId, siteId: siteId, label: label),
    secret: const HelmetSecretResult(keyVersion: 'v1', secretBase64: 'c2Vj'),
  );

  @override
  Future<HelmetMetaRecord> assignHelmet({
    required String helmetId,
    String? workerUid,
  }) async => HelmetMetaRecord(helmetId: helmetId, assignedWorkerId: workerUid);

  @override
  Future<HelmetMetaRecord> setHelmetSite({
    required String helmetId,
    String? siteId,
  }) async => HelmetMetaRecord(helmetId: helmetId, siteId: siteId);

  @override
  Future<HelmetMetaRecord> retireHelmet({required String helmetId}) async =>
      HelmetMetaRecord(helmetId: helmetId, provisioningStatus: 'revoked');

  @override
  Future<HelmetSecretResult> rotateHelmetSecret({
    required String helmetId,
  }) async =>
      const HelmetSecretResult(keyVersion: 'v2', secretBase64: 'c2VjMg==');

  @override
  Future<Site> upsertSite({
    String? siteId,
    required String name,
    String? description,
  }) async => Site(
    siteId: siteId ?? 'site-new',
    name: name,
    active: true,
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  @override
  Future<Site> setSiteSupervisors({
    required String siteId,
    required List<String> supervisorUids,
  }) async => Site(
    siteId: siteId,
    name: 'Site',
    active: true,
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  @override
  Future<HelmetConfiguration> setHelmetThresholds({
    required String helmetId,
    required HelmetConfiguration thresholds,
  }) async {
    setThresholdsCalls++;
    return thresholds;
  }
}

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('overview renders counts from the repository', (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = FakeAdminRepository(
      users: [
        _admin,
        _user(
          uid: 'sup-1',
          name: 'Sara Supervisor',
          email: 'sara@example.com',
          role: UserRole.supervisor,
        ),
        _user(
          uid: 'w-1',
          name: 'Waqar Worker',
          email: 'waqar@example.com',
          role: UserRole.worker,
        ),
        _user(
          uid: 'w-2',
          name: 'Bilal Worker',
          email: 'bilal@example.com',
          role: UserRole.worker,
        ),
        _user(
          uid: 'w-3',
          name: 'Omar Worker',
          email: 'omar@example.com',
          role: UserRole.worker,
          active: false,
        ),
      ],
      helmets: const [
        HelmetMetaRecord(
          helmetId: 'helmet001',
          provisioningStatus: 'provisioned',
          assignedWorkerId: 'w-1',
        ),
        HelmetMetaRecord(
          helmetId: 'helmet002',
          provisioningStatus: 'provisioned',
        ),
        HelmetMetaRecord(helmetId: 'helmet003', provisioningStatus: 'revoked'),
      ],
    );
    await tester.pumpWidget(
      _wrap(AdminOverviewScreen(admin: fake, onSignOut: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Users'), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // total users
    expect(find.text('Active users'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // active users
    expect(find.text('Helmets'), findsWidgets); // section title + tile label
    expect(find.text('Alerts today'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // alerts today (+ other 2s)
    expect(find.text('Critical unacknowledged'), findsOneWidget);
  });

  testWidgets('users list renders and filters by role', (tester) async {
    final fake = FakeAdminRepository(
      users: [
        _admin,
        _user(
          uid: 'sup-1',
          name: 'Sara Supervisor',
          email: 'sara@example.com',
          role: UserRole.supervisor,
        ),
        _user(
          uid: 'w-1',
          name: 'Waqar Worker',
          email: 'waqar@example.com',
          role: UserRole.worker,
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        AdminUsersScreen(admin: fake, currentUser: _admin, onSignOut: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Adam Admin'), findsOneWidget);
    expect(find.text('Sara Supervisor'), findsOneWidget);
    expect(find.text('Waqar Worker'), findsOneWidget);

    final workerFilter = find.descendant(
      of: find.byType(SegmentedFilter<UserRole?>),
      matching: find.text('Worker'),
    );
    await tester.tap(workerFilter);
    await tester.pumpAndSettle();

    expect(find.text('Waqar Worker'), findsOneWidget);
    expect(find.text('Sara Supervisor'), findsNothing);
    expect(find.text('Adam Admin'), findsNothing);
  });

  testWidgets('create-user form validates an empty email', (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = FakeAdminRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AdminUserEditScreen(admin: fake, currentUser: _admin),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create user'));
    await tester.pumpAndSettle();

    expect(find.text('Email is required.'), findsOneWidget);
    expect(fake.createUserCalls, 0);
  });

  testWidgets('thresholds form rejects warning >= critical', (tester) async {
    tester.view.physicalSize = const Size(1200, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = FakeAdminRepository(
      helmets: const [
        HelmetMetaRecord(
          helmetId: 'helmet001',
          provisioningStatus: 'provisioned',
        ),
      ],
      thresholds: {'helmet001': _config('helmet001')},
    );
    await tester.pumpWidget(
      _wrap(
        AdminThresholdsScreen(
          admin: fake,
          currentUser: _admin,
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final warningField = find.descendant(
      of: find.byKey(const ValueKey('temperatureWarningC')),
      matching: find.byType(TextField),
    );
    await tester.enterText(warningField, '45');
    await tester.tap(find.widgetWithText(FilledButton, 'Save thresholds'));
    await tester.pumpAndSettle();

    expect(find.textContaining('must be below'), findsWidgets);
    expect(fake.setThresholdsCalls, 0);
  });

  testWidgets('audit list renders entries and filters by target type', (
    tester,
  ) async {
    final fake = FakeAdminRepository(
      audit: [
        AuditLogEntry(
          id: 'a1',
          actorUid: 'admin-1',
          action: 'adminCreateUser',
          targetType: 'user',
          targetId: 'w-1',
          summary: 'Created worker Waqar',
          at: DateTime.utc(2026, 1, 2),
        ),
        AuditLogEntry(
          id: 'a2',
          actorUid: 'admin-1',
          action: 'adminRegisterHelmet',
          targetType: 'helmet',
          targetId: 'helmet001',
          summary: 'Registered helmet001',
          at: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(AdminAuditScreen(admin: fake, onSignOut: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Created worker Waqar'), findsOneWidget);
    expect(find.text('Registered helmet001'), findsOneWidget);

    final helmetFilter = find.descendant(
      of: find.byType(SegmentedFilter<String?>),
      matching: find.text('Helmets'),
    );
    await tester.tap(helmetFilter);
    await tester.pumpAndSettle();

    expect(find.text('Registered helmet001'), findsOneWidget);
    expect(find.text('Created worker Waqar'), findsNothing);
  });
}
