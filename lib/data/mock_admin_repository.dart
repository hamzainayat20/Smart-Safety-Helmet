import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../user_role.dart';
import 'admin_repository.dart';
import 'mock_repositories.dart';

/// Functional demo backend for the admin console.
///
/// Demo mode (`USE_DEMO_DATA=true`) runs every other part of the app on
/// [MockDataSet]; this repository does the same for administration, so the
/// console can be opened, exercised and demonstrated without a deployed
/// backend. All state is in-memory and seeded from the demo dataset:
/// changes last for the session only and are clearly demo data (accounts
/// are `@example.test`). The live path remains [FirebaseAdminRepository],
/// where the Cloud Functions enforce the same guards server-side.
///
/// Guards mirror the backend (`admin_service.js`): an administrator cannot
/// change their own role, deactivate or delete themselves, and the last
/// active administrator cannot be demoted, deactivated or deleted.
final class MockAdminRepository implements AdminRepository {
  MockAdminRepository(this.data, {this.actorUid = 'admin-demo'}) {
    _users = Map.of(data.users);
    _sites = Map.of(data.sites);
    _helmets = {
      for (final entry in data.helmets.entries)
        entry.key: HelmetMetaRecord(
          helmetId: entry.value.helmetId,
          siteId: entry.value.siteId,
          assignedWorkerId: entry.value.assignedWorkerId,
          provisioningStatus: entry.value.provisioningStatus.name,
          registeredAt: entry.value.updatedAt,
          registeredBy: 'demo-seed',
        ),
    };
    _thresholds = Map.of(data.configurations);
    _assignments = {
      for (final user in _users.values)
        user.uid: AdminUserAssignments(
          siteIds: user.siteIds,
          authorizedHelmetIds: user.authorizedHelmetIds,
          authorizedSupervisorIds: user.role == UserRole.worker
              ? const ['supervisor-demo']
              : const [],
        ),
    };
  }

  final MockDataSet data;

  /// The demo administrator operating the console.
  final String actorUid;

  late final Map<String, UserProfile> _users;
  late final Map<String, Site> _sites;
  late final Map<String, HelmetMetaRecord> _helmets;
  late final Map<String, HelmetConfiguration> _thresholds;
  late final Map<String, AdminUserAssignments> _assignments;
  final Map<String, Set<String>> _siteSupervisors = {};
  final Map<String, int> _keyVersions = {};
  final List<AuditLogEntry> _audit = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Random _random = Random.secure();
  int _sequence = 0;

  /// The demo repository fully serves reads and writes against the demo
  /// dataset, so the console treats it as operational (unlike
  /// [NoopAdminRepository], which refuses).
  @override
  bool get isLive => true;

  // --- helpers -------------------------------------------------------------

  Stream<T> _watch<T>(T Function() snapshot) async* {
    yield snapshot();
    await for (final _ in _changes.stream) {
      yield snapshot();
    }
  }

  void _touch() => _changes.add(null);

  DateTime _now() => DateTime.now().toUtc();

  Never _fail(String code, String message) =>
      throw RepositoryAccessException(code, message);

  UserProfile _requireUser(String uid) {
    final user = _users[uid];
    if (user == null) _fail('NOT_FOUND', 'No user exists with id $uid.');
    return user;
  }

  HelmetMetaRecord _requireHelmet(String helmetId) {
    final helmet = _helmets[helmetId];
    if (helmet == null) {
      _fail('NOT_FOUND', 'No helmet exists with id $helmetId.');
    }
    return helmet;
  }

  int get _activeAdministrators => _users.values
      .where((user) => user.role == UserRole.administrator && user.active)
      .length;

  void _guardNotSelf(String uid, String action) {
    if (uid == actorUid) {
      _fail('PERMISSION_DENIED', 'You cannot $action your own account.');
    }
  }

  void _guardNotLastAdmin(UserProfile target, String action) {
    if (target.role == UserRole.administrator &&
        target.active &&
        _activeAdministrators <= 1) {
      _fail(
        'FAILED_PRECONDITION',
        'This is the last active administrator and cannot be $action.',
      );
    }
  }

  UserProfile _rebuild(
    UserProfile user, {
    String? displayName,
    UserRole? role,
    bool? active,
    String? organizationName,
    bool clearOrganization = false,
    List<String>? siteIds,
    List<String>? authorizedHelmetIds,
  }) => UserProfile(
    schemaVersion: user.schemaVersion,
    uid: user.uid,
    displayName: displayName ?? user.displayName,
    email: user.email,
    role: role ?? user.role,
    active: active ?? user.active,
    organizationName: clearOrganization
        ? null
        : (organizationName ?? user.organizationName),
    siteIds: siteIds ?? user.siteIds,
    authorizedHelmetIds: authorizedHelmetIds ?? user.authorizedHelmetIds,
    pushAlertsEnabled: user.pushAlertsEnabled,
    criticalAlertsOnly: user.criticalAlertsOnly,
    vibrationEnabled: user.vibrationEnabled,
    updatedAt: _now(),
  );

  void _storeUser(UserProfile user) {
    _users[user.uid] = user;
    final previous = _assignments[user.uid];
    _assignments[user.uid] = AdminUserAssignments(
      siteIds: user.siteIds,
      authorizedHelmetIds: user.authorizedHelmetIds,
      authorizedSupervisorIds: previous?.authorizedSupervisorIds ?? const [],
    );
  }

  void _recordAudit({
    required String action,
    required String targetType,
    required String targetId,
    required String summary,
  }) {
    _audit.insert(
      0,
      AuditLogEntry(
        id: 'demo-audit-${++_sequence}',
        actorUid: actorUid,
        action: action,
        targetType: targetType,
        targetId: targetId,
        summary: summary,
        at: _now(),
      ),
    );
  }

  String _generateSecret() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  // --- reads ---------------------------------------------------------------

  @override
  Stream<List<UserProfile>> watchUsers() =>
      _watch(() => List.unmodifiable(_users.values));

  @override
  Stream<List<HelmetMetaRecord>> watchHelmetsMeta() =>
      _watch(() => List.unmodifiable(_helmets.values));

  @override
  Stream<List<Site>> watchSites() =>
      _watch(() => List.unmodifiable(_sites.values));

  @override
  Stream<HelmetConfiguration?> watchThresholds(String helmetId) =>
      _watch(() => _thresholds[helmetId]);

  @override
  Stream<List<AuditLogEntry>> watchAuditLog({int limit = 100}) =>
      _watch(() => List.unmodifiable(_audit.take(limit)));

  @override
  Stream<AdminOverview> watchOverview() => _watch(() {
    final now = _now();
    var alertsToday = 0;
    var criticalUnacknowledged = 0;
    for (final alert in data.alerts.values) {
      final received = alert.serverReceivedAt.toUtc();
      if (received.year == now.year &&
          received.month == now.month &&
          received.day == now.day) {
        alertsToday++;
      }
      if (alert.severity == SafetySeverity.critical &&
          alert.status != AlertStatus.acknowledged &&
          alert.status != AlertStatus.resolved) {
        criticalUnacknowledged++;
      }
    }
    return AdminOverview.from(
      users: _users.values.toList(),
      helmets: _helmets.values.toList(),
      alertsToday: alertsToday,
      criticalUnacknowledged: criticalUnacknowledged,
    );
  });

  @override
  Stream<List<AdminLiveHelmet>> watchLiveFleet() => _watch(() {
    final fleet =
        _helmets.values
            .map(
              (meta) => AdminLiveHelmet(
                meta: meta,
                current: data.readings[meta.helmetId],
                assessment: data.assessments[meta.helmetId],
              ),
            )
            .toList()
          ..sort((a, b) => a.helmetId.compareTo(b.helmetId));
    return List<AdminLiveHelmet>.unmodifiable(fleet);
  });

  @override
  Stream<List<SafetyAlert>> watchRecentAlerts({int limit = 50}) =>
      _watch(() {
        final alerts = data.alerts.values.toList()
          ..sort((a, b) => b.serverReceivedAt.compareTo(a.serverReceivedAt));
        return List<SafetyAlert>.unmodifiable(alerts.take(limit));
      });

  /// Demo data is local, so the demo "backend" is always reachable.
  @override
  Stream<bool> watchBackendConnection() => Stream.value(true);

  @override
  Future<AdminUserAssignments> getUserAssignments(String uid) async {
    _requireUser(uid);
    return _assignments[uid] ?? const AdminUserAssignments();
  }

  // --- user writes -----------------------------------------------------------

  @override
  Future<CreatedUserResult> createUser({
    required String email,
    required String name,
    required UserRole role,
    String? organizationName,
    List<String> siteIds = const [],
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (_users.values.any((user) => user.email.toLowerCase() == normalizedEmail)) {
      _fail('ALREADY_EXISTS', 'A user with this email already exists.');
    }
    final uid = 'demo-user-${++_sequence}';
    final user = UserProfile(
      uid: uid,
      displayName: name.trim(),
      email: normalizedEmail,
      role: role,
      active: true,
      organizationName: organizationName,
      siteIds: siteIds,
      updatedAt: _now(),
    );
    _storeUser(user);
    _recordAudit(
      action: 'createUser',
      targetType: 'user',
      targetId: uid,
      summary: 'Created ${role.name} account for ${user.email} (demo).',
    );
    _touch();
    return CreatedUserResult(
      uid: uid,
      user: user,
      passwordSetupLink: 'https://demo.example.test/setup/$uid',
    );
  }

  @override
  Future<UserProfile> setUserRole({
    required String uid,
    required UserRole role,
  }) async {
    final target = _requireUser(uid);
    _guardNotSelf(uid, 'change the role of');
    if (role != UserRole.administrator) {
      _guardNotLastAdmin(target, 'demoted');
    }
    final updated = _rebuild(target, role: role);
    _storeUser(updated);
    _recordAudit(
      action: 'setUserRole',
      targetType: 'user',
      targetId: uid,
      summary: 'Role of ${target.email} changed to ${role.name} (demo).',
    );
    _touch();
    return updated;
  }

  @override
  Future<UserProfile> setUserActive({
    required String uid,
    required bool active,
  }) async {
    final target = _requireUser(uid);
    if (!active) {
      _guardNotSelf(uid, 'deactivate');
      _guardNotLastAdmin(target, 'deactivated');
    }
    final updated = _rebuild(target, active: active);
    _storeUser(updated);
    _recordAudit(
      action: 'setUserActive',
      targetType: 'user',
      targetId: uid,
      summary:
          '${target.email} ${active ? 'activated' : 'deactivated'} (demo).',
    );
    _touch();
    return updated;
  }

  @override
  Future<UserProfile> updateUserProfile({
    required String uid,
    String? name,
    String? organizationName,
  }) async {
    final target = _requireUser(uid);
    final updated = _rebuild(
      target,
      displayName: name?.trim(),
      organizationName: organizationName,
    );
    _storeUser(updated);
    _recordAudit(
      action: 'updateUserProfile',
      targetType: 'user',
      targetId: uid,
      summary: 'Profile of ${target.email} updated (demo).',
    );
    _touch();
    return updated;
  }

  @override
  Future<UserProfile> updateUserAssignments({
    required String uid,
    List<String>? siteIds,
    List<String>? authorizedHelmetIds,
    List<String>? authorizedSupervisorIds,
  }) async {
    final target = _requireUser(uid);
    final previous = _assignments[uid] ?? const AdminUserAssignments();
    _assignments[uid] = AdminUserAssignments(
      siteIds: siteIds ?? previous.siteIds,
      authorizedHelmetIds:
          authorizedHelmetIds ?? previous.authorizedHelmetIds,
      authorizedSupervisorIds:
          authorizedSupervisorIds ?? previous.authorizedSupervisorIds,
    );
    final updated = _rebuild(
      target,
      siteIds: siteIds ?? target.siteIds,
      authorizedHelmetIds: authorizedHelmetIds ?? target.authorizedHelmetIds,
    );
    _users[uid] = updated;
    _recordAudit(
      action: 'updateUserAssignments',
      targetType: 'user',
      targetId: uid,
      summary: 'Assignments of ${target.email} updated (demo).',
    );
    _touch();
    return updated;
  }

  @override
  Future<void> deleteUser({required String uid}) async {
    final target = _requireUser(uid);
    _guardNotSelf(uid, 'delete');
    _guardNotLastAdmin(target, 'deleted');
    _users.remove(uid);
    _assignments.remove(uid);
    _recordAudit(
      action: 'deleteUser',
      targetType: 'user',
      targetId: uid,
      summary: 'Deleted account ${target.email} (demo).',
    );
    _touch();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    // Demo mode has no mail transport; the action succeeds silently so the
    // flow can be demonstrated. Live mode sends a real Firebase email.
  }

  // --- helmet writes ---------------------------------------------------------

  @override
  Future<RegisteredHelmetResult> registerHelmet({
    required String helmetId,
    String? siteId,
    String? label,
  }) async {
    final id = helmetId.trim();
    if (_helmets.containsKey(id)) {
      _fail('ALREADY_EXISTS', 'A helmet with id $id already exists.');
    }
    if (siteId != null && !_sites.containsKey(siteId)) {
      _fail('NOT_FOUND', 'No site exists with id $siteId.');
    }
    final meta = HelmetMetaRecord(
      helmetId: id,
      siteId: siteId,
      label: label,
      provisioningStatus: 'provisioned',
      registeredAt: _now(),
      registeredBy: actorUid,
    );
    _helmets[id] = meta;
    _keyVersions[id] = 1;
    final secret = HelmetSecretResult(
      keyVersion: 'v1',
      secretBase64: _generateSecret(),
    );
    _recordAudit(
      action: 'registerHelmet',
      targetType: 'helmet',
      targetId: id,
      summary: 'Registered helmet $id with device secret v1 (demo).',
    );
    _touch();
    return RegisteredHelmetResult(helmet: meta, secret: secret);
  }

  @override
  Future<HelmetMetaRecord> assignHelmet({
    required String helmetId,
    String? workerUid,
  }) async {
    final helmet = _requireHelmet(helmetId);
    if (helmet.isRevoked) {
      _fail('FAILED_PRECONDITION', 'A revoked helmet cannot be assigned.');
    }
    if (workerUid != null) {
      final worker = _requireUser(workerUid);
      if (worker.role != UserRole.worker) {
        _fail('FAILED_PRECONDITION', 'Helmets can only be assigned to workers.');
      }
    }
    // Keep workers' authorizedHelmetIds in sync, both directions.
    final previousWorkerId = helmet.assignedWorkerId;
    if (previousWorkerId != null && previousWorkerId != workerUid) {
      final previous = _users[previousWorkerId];
      if (previous != null) {
        _storeUser(
          _rebuild(
            previous,
            authorizedHelmetIds: previous.authorizedHelmetIds
                .where((id) => id != helmetId)
                .toList(),
          ),
        );
      }
    }
    if (workerUid != null) {
      final worker = _users[workerUid]!;
      if (!worker.authorizedHelmetIds.contains(helmetId)) {
        _storeUser(
          _rebuild(
            worker,
            authorizedHelmetIds: [...worker.authorizedHelmetIds, helmetId],
          ),
        );
      }
    }
    final updated = HelmetMetaRecord(
      helmetId: helmet.helmetId,
      siteId: helmet.siteId,
      assignedWorkerId: workerUid,
      label: helmet.label,
      provisioningStatus: helmet.provisioningStatus,
      registeredAt: helmet.registeredAt,
      registeredBy: helmet.registeredBy,
    );
    _helmets[helmetId] = updated;
    _recordAudit(
      action: 'assignHelmet',
      targetType: 'helmet',
      targetId: helmetId,
      summary: workerUid == null
          ? 'Helmet $helmetId unassigned (demo).'
          : 'Helmet $helmetId assigned to $workerUid (demo).',
    );
    _touch();
    return updated;
  }

  @override
  Future<HelmetMetaRecord> setHelmetSite({
    required String helmetId,
    String? siteId,
  }) async {
    final helmet = _requireHelmet(helmetId);
    if (siteId != null && !_sites.containsKey(siteId)) {
      _fail('NOT_FOUND', 'No site exists with id $siteId.');
    }
    final updated = HelmetMetaRecord(
      helmetId: helmet.helmetId,
      siteId: siteId,
      assignedWorkerId: helmet.assignedWorkerId,
      label: helmet.label,
      provisioningStatus: helmet.provisioningStatus,
      registeredAt: helmet.registeredAt,
      registeredBy: helmet.registeredBy,
    );
    _helmets[helmetId] = updated;
    _recordAudit(
      action: 'setHelmetSite',
      targetType: 'helmet',
      targetId: helmetId,
      summary: 'Helmet $helmetId moved to site ${siteId ?? 'none'} (demo).',
    );
    _touch();
    return updated;
  }

  @override
  Future<HelmetMetaRecord> retireHelmet({required String helmetId}) async {
    final helmet = _requireHelmet(helmetId);
    if (helmet.assignedWorkerId != null) {
      await assignHelmet(helmetId: helmetId, workerUid: null);
    }
    final current = _helmets[helmetId]!;
    final updated = HelmetMetaRecord(
      helmetId: current.helmetId,
      siteId: current.siteId,
      label: current.label,
      provisioningStatus: 'revoked',
      registeredAt: current.registeredAt,
      registeredBy: current.registeredBy,
    );
    _helmets[helmetId] = updated;
    _keyVersions.remove(helmetId);
    _recordAudit(
      action: 'retireHelmet',
      targetType: 'helmet',
      targetId: helmetId,
      summary: 'Helmet $helmetId retired; device secret revoked (demo).',
    );
    _touch();
    return updated;
  }

  @override
  Future<HelmetSecretResult> rotateHelmetSecret({
    required String helmetId,
  }) async {
    final helmet = _requireHelmet(helmetId);
    if (helmet.isRevoked) {
      _fail('FAILED_PRECONDITION', 'A revoked helmet has no active secret.');
    }
    final version = (_keyVersions[helmetId] ?? 1) + 1;
    _keyVersions[helmetId] = version;
    final secret = HelmetSecretResult(
      keyVersion: 'v$version',
      secretBase64: _generateSecret(),
    );
    _recordAudit(
      action: 'rotateHelmetSecret',
      targetType: 'helmet',
      targetId: helmetId,
      summary: 'Device secret for $helmetId rotated to v$version (demo).',
    );
    _touch();
    return secret;
  }

  // --- site writes -----------------------------------------------------------

  @override
  Future<Site> upsertSite({
    String? siteId,
    required String name,
    String? description,
  }) async {
    final id = siteId ??
        'site-${name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}'
            '-${++_sequence}';
    final existing = _sites[id];
    final site = Site(
      schemaVersion: existing?.schemaVersion ?? currentSchemaVersion,
      siteId: id,
      name: name.trim(),
      organizationName: existing?.organizationName,
      zones: existing?.zones ?? const [],
      active: existing?.active ?? true,
      updatedAt: _now(),
    );
    _sites[id] = site;
    _recordAudit(
      action: 'upsertSite',
      targetType: 'site',
      targetId: id,
      summary: existing == null
          ? 'Created site ${site.name} (demo).'
          : 'Updated site ${site.name} (demo).',
    );
    _touch();
    return site;
  }

  @override
  Future<Site> setSiteSupervisors({
    required String siteId,
    required List<String> supervisorUids,
  }) async {
    final site = _sites[siteId];
    if (site == null) _fail('NOT_FOUND', 'No site exists with id $siteId.');
    for (final uid in supervisorUids) {
      final user = _requireUser(uid);
      if (user.role != UserRole.supervisor &&
          user.role != UserRole.administrator) {
        _fail(
          'FAILED_PRECONDITION',
          'Only supervisors or administrators can be site supervisors.',
        );
      }
    }
    final previous = _siteSupervisors[siteId] ?? const <String>{};
    final next = supervisorUids.toSet();
    for (final uid in previous.difference(next)) {
      final user = _users[uid];
      if (user != null) {
        _storeUser(
          _rebuild(
            user,
            siteIds: user.siteIds.where((id) => id != siteId).toList(),
          ),
        );
      }
    }
    for (final uid in next.difference(previous)) {
      final user = _users[uid]!;
      if (!user.siteIds.contains(siteId)) {
        _storeUser(_rebuild(user, siteIds: [...user.siteIds, siteId]));
      }
    }
    _siteSupervisors[siteId] = next;
    _recordAudit(
      action: 'setSiteSupervisors',
      targetType: 'site',
      targetId: siteId,
      summary: 'Supervisors of ${site.name} updated (demo).',
    );
    _touch();
    return site;
  }

  // --- thresholds --------------------------------------------------------------

  @override
  Future<HelmetConfiguration> setHelmetThresholds({
    required String helmetId,
    required HelmetConfiguration thresholds,
  }) async {
    _requireHelmet(helmetId);
    _thresholds[helmetId] = thresholds;
    _recordAudit(
      action: 'setHelmetThresholds',
      targetType: 'config',
      targetId: helmetId,
      summary: 'Thresholds for helmet $helmetId updated (demo).',
    );
    _touch();
    return thresholds;
  }
}
