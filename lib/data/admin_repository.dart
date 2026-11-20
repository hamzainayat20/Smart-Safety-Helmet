import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../user_role.dart';
import 'firebase_realtime_repositories.dart' show parseCurrentReadingRecord;

/// A helmet's `/helmets/{id}/meta` record, as written by the admin backend
/// (registration, assignment, retirement). Telemetry-owned nodes (`current`,
/// `currentAssessment`) are deliberately not part of this record.
final class HelmetMetaRecord {
  const HelmetMetaRecord({
    required this.helmetId,
    this.siteId,
    this.assignedWorkerId,
    this.label,
    this.provisioningStatus,
    this.registeredAt,
    this.registeredBy,
  });

  final String helmetId;
  final String? siteId;
  final String? assignedWorkerId;
  final String? label;

  /// Raw status string from the backend ('provisioned', 'revoked', ...).
  /// Null when the stored record does not carry one.
  final String? provisioningStatus;
  final DateTime? registeredAt;
  final String? registeredBy;

  bool get isRevoked => provisioningStatus == 'revoked';
  bool get isAssigned => assignedWorkerId != null;

  factory HelmetMetaRecord.fromMap(String helmetId, Map<String, dynamic> map) =>
      HelmetMetaRecord(
        helmetId: helmetId,
        siteId: _stringOrNull(map['siteId']),
        assignedWorkerId: _stringOrNull(map['assignedWorkerId']),
        label: _stringOrNull(map['label']),
        provisioningStatus: _stringOrNull(map['provisioningStatus']),
        registeredAt: _dateOrNull(map['registeredAt']),
        registeredBy: _stringOrNull(map['registeredBy']),
      );
}

/// One `/adminAudit/{pushKey}` entry. Secret values are never part of an
/// audit record; the backend stores only key versions for secret actions.
final class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.actorUid,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.summary,
    this.at,
    this.before,
    this.after,
  });

  final String id;
  final String actorUid;
  final String action;

  /// 'user' | 'helmet' | 'site' | 'config'
  final String targetType;
  final String targetId;
  final String summary;
  final DateTime? at;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;

  factory AuditLogEntry.fromMap(String id, Map<String, dynamic> map) =>
      AuditLogEntry(
        id: id,
        actorUid: map['actorUid']?.toString() ?? '',
        action: map['action']?.toString() ?? '',
        targetType: map['targetType']?.toString() ?? '',
        targetId: map['targetId']?.toString() ?? '',
        summary: map['summary']?.toString() ?? '',
        at: _dateOrNull(map['at']),
        before: _mapOrNull(map['before']),
        after: _mapOrNull(map['after']),
      );
}

/// The three assignment maps of a user record. [UserProfile] does not carry
/// `authorizedSupervisorIds`, so the admin console reads assignments from the
/// raw record through this class.
final class AdminUserAssignments {
  const AdminUserAssignments({
    this.siteIds = const [],
    this.authorizedHelmetIds = const [],
    this.authorizedSupervisorIds = const [],
  });

  final List<String> siteIds;
  final List<String> authorizedHelmetIds;
  final List<String> authorizedSupervisorIds;

  factory AdminUserAssignments.fromMap(Map<String, dynamic> map) =>
      AdminUserAssignments(
        siteIds: _idList(map['siteIds']),
        authorizedHelmetIds: _idList(map['authorizedHelmetIds']),
        authorizedSupervisorIds: _idList(map['authorizedSupervisorIds']),
      );
}

/// Counts for the admin overview. Alert counts are nullable: when the
/// `/alerts` node cannot be read they stay unknown and render as "—",
/// never as zero.
final class AdminOverview {
  const AdminOverview({
    required this.totalUsers,
    required this.activeUsers,
    required this.administrators,
    required this.supervisors,
    required this.workers,
    required this.totalHelmets,
    required this.provisionedHelmets,
    required this.assignedHelmets,
    required this.unassignedHelmets,
    required this.revokedHelmets,
    this.alertsToday,
    this.criticalUnacknowledged,
  });

  final int totalUsers;
  final int activeUsers;
  final int administrators;
  final int supervisors;
  final int workers;
  final int totalHelmets;
  final int provisionedHelmets;
  final int assignedHelmets;
  final int unassignedHelmets;
  final int revokedHelmets;
  final int? alertsToday;
  final int? criticalUnacknowledged;

  factory AdminOverview.from({
    required List<UserProfile> users,
    required List<HelmetMetaRecord> helmets,
    int? alertsToday,
    int? criticalUnacknowledged,
  }) => AdminOverview(
    totalUsers: users.length,
    activeUsers: users.where((user) => user.active).length,
    administrators: users
        .where((user) => user.role == UserRole.administrator)
        .length,
    supervisors: users.where((user) => user.role == UserRole.supervisor).length,
    workers: users.where((user) => user.role == UserRole.worker).length,
    totalHelmets: helmets.length,
    provisionedHelmets: helmets
        .where((helmet) => helmet.provisioningStatus == 'provisioned')
        .length,
    assignedHelmets: helmets
        .where((helmet) => helmet.isAssigned && !helmet.isRevoked)
        .length,
    unassignedHelmets: helmets
        .where((helmet) => !helmet.isAssigned && !helmet.isRevoked)
        .length,
    revokedHelmets: helmets.where((helmet) => helmet.isRevoked).length,
    alertsToday: alertsToday,
    criticalUnacknowledged: criticalUnacknowledged,
  );
}

/// Result of `adminCreateUser`: the created profile plus the one-time
/// password setup link the admin shares with the new user out-of-band.
final class CreatedUserResult {
  const CreatedUserResult({
    required this.uid,
    required this.user,
    required this.passwordSetupLink,
  });

  final String uid;
  final UserProfile user;
  final String passwordSetupLink;
}

/// A device secret returned exactly once (registration or rotation).
final class HelmetSecretResult {
  const HelmetSecretResult({
    required this.keyVersion,
    required this.secretBase64,
  });

  final String keyVersion;
  final String secretBase64;
}

/// Result of `adminRegisterHelmet`: the new meta record plus its one-time
/// device secret.
final class RegisteredHelmetResult {
  const RegisteredHelmetResult({required this.helmet, required this.secret});

  final HelmetMetaRecord helmet;
  final HelmetSecretResult secret;
}

/// One helmet as the admin live monitor sees it: the registry record plus
/// the telemetry projections (`current`, `currentAssessment`) that the
/// ingestion backend keeps up to date under `/helmets/{id}`.
final class AdminLiveHelmet {
  const AdminLiveHelmet({
    required this.meta,
    this.current,
    this.assessment,
    this.telemetryUnreadable = false,
  });

  final HelmetMetaRecord meta;

  /// Latest validated reading, or null when the helmet has never reported.
  final SensorReading? current;

  /// Latest AI assessment for the helmet, when one exists.
  final SafetyAssessment? assessment;

  /// True when a `current` node exists but could not be parsed. Rendered as
  /// unreadable telemetry, never as "no data" and never as safe.
  final bool telemetryUnreadable;

  String get helmetId => meta.helmetId;
}

String? _stringOrNull(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

DateTime? _dateOrNull(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}

Map<String, dynamic>? _mapOrNull(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return null;
}

List<String> _idList(Object? value) {
  if (value is Map) {
    return List.unmodifiable(
      value.entries
          .where((entry) => entry.value == true)
          .map((entry) => entry.key.toString().trim())
          .where((id) => id.isNotEmpty)
          .toList()
        ..sort(),
    );
  }
  if (value is List) {
    return List.unmodifiable(
      value
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
    );
  }
  return const [];
}

/// Admin console data access. Reads go straight to RTDB with the admin
/// token; every write goes through an `admin*` Cloud Function callable so
/// the backend can enforce guards (self-protection, last-admin) and write
/// the audit log.
abstract interface class AdminRepository {
  /// True when this repository fully serves admin reads and writes —
  /// the live Firebase implementation, or the functional demo backend
  /// over the demo dataset. The Noop repository returns false and the
  /// console refuses to operate rather than fake administrative data.
  bool get isLive;

  Stream<List<UserProfile>> watchUsers();
  Stream<List<HelmetMetaRecord>> watchHelmetsMeta();
  Stream<List<Site>> watchSites();
  Stream<HelmetConfiguration?> watchThresholds(String helmetId);
  Stream<List<AuditLogEntry>> watchAuditLog({int limit = 100});
  Stream<AdminOverview> watchOverview();

  /// Every helmet with its latest reading and AI assessment, re-emitted on
  /// every telemetry write (real time).
  Stream<List<AdminLiveHelmet>> watchLiveFleet();

  /// The newest stored alerts across the whole fleet, newest first.
  /// Bounded: at most [FirebaseAdminRepository.maxFleetAlertQuery].
  Stream<List<SafetyAlert>> watchRecentAlerts({int limit = 50});

  /// Whether the app currently holds a live connection to the database.
  Stream<bool> watchBackendConnection();

  Future<AdminUserAssignments> getUserAssignments(String uid);

  Future<CreatedUserResult> createUser({
    required String email,
    required String name,
    required UserRole role,
    String? organizationName,
    List<String> siteIds = const [],
  });
  Future<UserProfile> setUserRole({
    required String uid,
    required UserRole role,
  });
  Future<UserProfile> setUserActive({
    required String uid,
    required bool active,
  });
  Future<UserProfile> updateUserProfile({
    required String uid,
    String? name,
    String? organizationName,
  });
  Future<UserProfile> updateUserAssignments({
    required String uid,
    List<String>? siteIds,
    List<String>? authorizedHelmetIds,
    List<String>? authorizedSupervisorIds,
  });
  Future<void> deleteUser({required String uid});

  /// Sends a Firebase Auth password-reset email. Client-side by design;
  /// there is deliberately no callable for this.
  Future<void> sendPasswordReset(String email);

  Future<RegisteredHelmetResult> registerHelmet({
    required String helmetId,
    String? siteId,
    String? label,
  });
  Future<HelmetMetaRecord> assignHelmet({
    required String helmetId,
    String? workerUid,
  });
  Future<HelmetMetaRecord> setHelmetSite({
    required String helmetId,
    String? siteId,
  });
  Future<HelmetMetaRecord> retireHelmet({required String helmetId});
  Future<HelmetSecretResult> rotateHelmetSecret({required String helmetId});

  Future<Site> upsertSite({
    String? siteId,
    required String name,
    String? description,
  });
  Future<Site> setSiteSupervisors({
    required String siteId,
    required List<String> supervisorUids,
  });

  Future<HelmetConfiguration> setHelmetThresholds({
    required String helmetId,
    required HelmetConfiguration thresholds,
  });
}

RepositoryAccessException _adminFailure(Object error) {
  if (error is RepositoryAccessException) return error;
  if (error is FirebaseFunctionsException) {
    final code = switch (error.code) {
      'permission-denied' || 'unauthenticated' => 'PERMISSION_DENIED',
      'not-found' => 'NOT_FOUND',
      'already-exists' => 'ALREADY_EXISTS',
      'failed-precondition' => 'FAILED_PRECONDITION',
      'invalid-argument' => 'INVALID_ARGUMENT',
      _ => 'BACKEND_ERROR',
    };
    return RepositoryAccessException(
      code,
      error.message ?? 'The admin operation could not be completed.',
    );
  }
  if (error is FirebaseException &&
      (error.code == 'permission-denied' ||
          error.code == 'permission_denied')) {
    return const RepositoryAccessException(
      'PERMISSION_DENIED',
      'Permission denied for the requested admin data.',
    );
  }
  if (error is FirebaseAuthException) {
    return RepositoryAccessException(
      'AUTH_ERROR',
      error.message ?? 'The email could not be sent.',
    );
  }
  return const RepositoryAccessException(
    'BACKEND_ERROR',
    'The live backend is unavailable. Try again.',
  );
}

/// Maps database errors on a live stream to [RepositoryAccessException].
///
/// A transformer (not `try { yield* source }`): errors emitted by a stream
/// passed to `yield*` are forwarded as-is and never reach a `catch`, which
/// left raw FirebaseExceptions reaching the UI as "Something went wrong".
Stream<T> _guardAdminStream<T>(Stream<T> source) => source.transform(
  StreamTransformer<T, T>.fromHandlers(
    handleError: (error, stackTrace, sink) =>
        sink.addError(_adminFailure(error), stackTrace),
  ),
);

Future<T> _guardAdminRequest<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on Object catch (error) {
    throw _adminFailure(error);
  }
}

Map<String, dynamic>? _optionalRecordOf(Object? value) {
  if (value == null) return null;
  if (value is! Map) return null;
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}

/// Combines two streams, emitting only once both have produced a value.
Stream<R> _combineLatest2<A, B, R>(
  Stream<A> first,
  Stream<B> second,
  R Function(A first, B second) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? firstSubscription;
  StreamSubscription<B>? secondSubscription;
  A? firstValue;
  B? secondValue;
  var hasFirst = false;
  var hasSecond = false;

  void emit() {
    if (hasFirst && hasSecond && !controller.isClosed) {
      controller.add(combine(firstValue as A, secondValue as B));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      firstSubscription = first.listen((value) {
        firstValue = value;
        hasFirst = true;
        emit();
      }, onError: controller.addError);
      secondSubscription = second.listen((value) {
        secondValue = value;
        hasSecond = true;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await firstSubscription?.cancel();
      await secondSubscription?.cancel();
    },
  );
  return controller.stream;
}

/// Combines three streams, emitting only once all have produced a value.
Stream<R> _combineLatest3<A, B, C, R>(
  Stream<A> first,
  Stream<B> second,
  Stream<C> third,
  R Function(A first, B second, C third) combine,
) => _combineLatest2<(A, B), C, R>(
  _combineLatest2<A, B, (A, B)>(first, second, (a, b) => (a, b)),
  third,
  (pair, c) => combine(pair.$1, pair.$2, c),
);

final class FirebaseAdminRepository implements AdminRepository {
  FirebaseAdminRepository({
    FirebaseFunctions? functions,
    FirebaseDatabase? database,
    FirebaseAuth? auth,
  }) : _functions = functions ?? FirebaseFunctions.instance,
       _database = database ?? FirebaseDatabase.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseDatabase _database;
  final FirebaseAuth _auth;

  @override
  bool get isLive => true;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> payload,
  ) => _guardAdminRequest(() async {
    final result = await _functions.httpsCallable(name).call(payload);
    return _optionalRecordOf(result.data) ?? const {};
  });

  UserProfile _parseUser(String uid, Map<String, dynamic> record) {
    final data = Map<String, dynamic>.of(record);
    data['uid'] ??= uid;
    data['schemaVersion'] ??= currentSchemaVersion;
    return UserProfile.fromJson(data);
  }

  UserProfile _userFromResponse(Map<String, dynamic> data, String uid) {
    final record = _optionalRecordOf(data['user']);
    if (record == null) {
      throw const RepositoryAccessException(
        'BACKEND_ERROR',
        'The backend returned an incomplete user record.',
      );
    }
    return _parseUser(uid, record);
  }

  Site _parseSite(String siteId, Map<String, dynamic> record) {
    final data = Map<String, dynamic>.of(record);
    data['siteId'] ??= siteId;
    data['schemaVersion'] ??= currentSchemaVersion;
    data['active'] ??= true;
    data['updatedAt'] ??= 0;
    return Site.fromJson(data);
  }

  Site _siteFromResponse(Map<String, dynamic> data) {
    final record = _optionalRecordOf(data['site']);
    if (record == null) {
      throw const RepositoryAccessException(
        'BACKEND_ERROR',
        'The backend returned an incomplete site record.',
      );
    }
    return _parseSite(record['siteId']?.toString() ?? '', record);
  }

  HelmetMetaRecord _helmetFromResponse(Map<String, dynamic> data) {
    final record = _optionalRecordOf(data['helmet']);
    if (record == null) {
      throw const RepositoryAccessException(
        'BACKEND_ERROR',
        'The backend returned an incomplete helmet record.',
      );
    }
    return HelmetMetaRecord.fromMap(
      record['helmetId']?.toString() ?? '',
      record,
    );
  }

  HelmetSecretResult _secretFromResponse(Map<String, dynamic> data) {
    final record = _optionalRecordOf(data['deviceSecret']);
    final secret = record?['secretBase64']?.toString();
    if (record == null || secret == null || secret.isEmpty) {
      throw const RepositoryAccessException(
        'BACKEND_ERROR',
        'The backend did not return a device secret.',
      );
    }
    return HelmetSecretResult(
      keyVersion: record['keyVersion']?.toString() ?? 'v1',
      secretBase64: secret,
    );
  }

  @override
  Stream<List<UserProfile>> watchUsers() => _guardAdminStream(
    _database.ref('users').onValue.map((event) {
      final root = _optionalRecordOf(event.snapshot.value);
      if (root == null) return const <UserProfile>[];
      final users = <UserProfile>[];
      for (final entry in root.entries) {
        final record = _optionalRecordOf(entry.value);
        if (record == null) continue;
        try {
          users.add(_parseUser(entry.key, record));
        } on Object {
          // A single malformed legacy record must not hide every other
          // user from the administrator.
          continue;
        }
      }
      users.sort((a, b) => a.displayName.compareTo(b.displayName));
      return List<UserProfile>.unmodifiable(users);
    }),
  );

  @override
  Stream<List<HelmetMetaRecord>> watchHelmetsMeta() => _guardAdminStream(
    _database.ref('helmets').onValue.map((event) {
      final root = _optionalRecordOf(event.snapshot.value);
      if (root == null) return const <HelmetMetaRecord>[];
      final helmets = <HelmetMetaRecord>[];
      for (final entry in root.entries) {
        final node = _optionalRecordOf(entry.value);
        final meta = _optionalRecordOf(node?['meta']);
        if (meta == null) continue;
        helmets.add(HelmetMetaRecord.fromMap(entry.key, meta));
      }
      helmets.sort((a, b) => a.helmetId.compareTo(b.helmetId));
      return List<HelmetMetaRecord>.unmodifiable(helmets);
    }),
  );

  @override
  Stream<List<Site>> watchSites() => _guardAdminStream(
    _database.ref('sites').onValue.map((event) {
      final root = _optionalRecordOf(event.snapshot.value);
      if (root == null) return const <Site>[];
      final sites = <Site>[];
      for (final entry in root.entries) {
        final record = _optionalRecordOf(entry.value);
        if (record == null) continue;
        try {
          sites.add(_parseSite(entry.key, record));
        } on Object {
          continue;
        }
      }
      sites.sort((a, b) => a.name.compareTo(b.name));
      return List<Site>.unmodifiable(sites);
    }),
  );

  @override
  Stream<HelmetConfiguration?> watchThresholds(String helmetId) {
    final defaults = _guardAdminStream(
      _database
          .ref('config/defaults')
          .onValue
          .map((event) => _optionalRecordOf(event.snapshot.value)),
    );
    final helmet = _guardAdminStream(
      _database
          .ref('config/helmets/$helmetId')
          .onValue
          .map((event) => _optionalRecordOf(event.snapshot.value)),
    );
    return _combineLatest2(defaults, helmet, (defaultsRecord, helmetRecord) {
      if (defaultsRecord == null && helmetRecord == null) return null;
      final merged = <String, dynamic>{
        ...?defaultsRecord,
        ...?helmetRecord,
        'helmetId': helmetId,
      };
      merged['schemaVersion'] ??= currentSchemaVersion;
      merged['configVersion'] ??= '1.0';
      merged['updatedBy'] ??= 'system-default';
      merged['updatedAt'] ??= 0;
      try {
        return HelmetConfiguration.fromJson(merged);
      } on Object {
        return null;
      }
    });
  }

  @override
  Stream<List<AuditLogEntry>> watchAuditLog({int limit = 100}) =>
      _guardAdminStream(
        _database.ref('adminAudit').limitToLast(limit).onValue.map((event) {
          final root = _optionalRecordOf(event.snapshot.value);
          if (root == null) return const <AuditLogEntry>[];
          final entries = <AuditLogEntry>[];
          for (final entry in root.entries) {
            final record = _optionalRecordOf(entry.value);
            if (record == null) continue;
            entries.add(AuditLogEntry.fromMap(entry.key, record));
          }
          entries.sort((a, b) {
            final atA = a.at?.millisecondsSinceEpoch ?? 0;
            final atB = b.at?.millisecondsSinceEpoch ?? 0;
            if (atB != atA) return atB.compareTo(atA);
            return b.id.compareTo(a.id);
          });
          return List<AuditLogEntry>.unmodifiable(entries);
        }),
      );

  /// Largest fleet-wide alert query the database rules allow an
  /// administrator (`alerts/.read` in database.rules.json).
  static const int maxFleetAlertQuery = 500;

  Stream<List<SafetyAlert>> _fleetAlerts(int limit) {
    final bounded = limit < 1
        ? 1
        : (limit > maxFleetAlertQuery ? maxFleetAlertQuery : limit);
    return _database
        .ref('alerts')
        .orderByChild('serverReceivedAt')
        .limitToLast(bounded)
        .onValue
        .map((event) {
          final root = _optionalRecordOf(event.snapshot.value);
          if (root == null) return const <SafetyAlert>[];
          final alerts = <SafetyAlert>[];
          for (final entry in root.entries) {
            final record = _optionalRecordOf(entry.value);
            if (record == null) continue;
            record['alertId'] ??= entry.key;
            record['schemaVersion'] ??= currentSchemaVersion;
            try {
              alerts.add(SafetyAlert.fromJson(record));
            } on Object {
              // One malformed alert must not hide the rest of the feed.
              continue;
            }
          }
          alerts.sort(
            (a, b) => b.serverReceivedAt.compareTo(a.serverReceivedAt),
          );
          return List<SafetyAlert>.unmodifiable(alerts);
        });
  }

  Stream<(int?, int?)> _watchAlertCounts() => _fleetAlerts(maxFleetAlertQuery)
      .map<(int?, int?)>((alerts) {
        final now = DateTime.now().toUtc();
        final todayStart = DateTime.utc(now.year, now.month, now.day);
        var today = 0;
        var criticalOpen = 0;
        for (final alert in alerts) {
          if (!alert.serverReceivedAt.isBefore(todayStart)) today++;
          if (alert.severity == SafetySeverity.critical &&
              alert.status != AlertStatus.acknowledged &&
              alert.status != AlertStatus.resolved) {
            criticalOpen++;
          }
        }
        return (today, criticalOpen);
      })
      .transform(
        // Alert counts are an overview extra: when /alerts cannot be read the
        // counts stay unknown ("—") rather than failing the whole overview.
        StreamTransformer<(int?, int?), (int?, int?)>.fromHandlers(
          handleError: (error, stackTrace, sink) => sink.add((null, null)),
        ),
      );

  SafetyAssessment? _parseAssessment(Object? value, String helmetId) {
    final data = _optionalRecordOf(value);
    if (data == null) return null;
    data['helmetId'] ??= helmetId;
    data['assessmentId'] ??= data['eventId'];
    data['schemaVersion'] ??= '1.0';
    try {
      return SafetyAssessment.fromJson(data);
    } on Object {
      return null;
    }
  }

  @override
  Stream<List<AdminLiveHelmet>> watchLiveFleet() => _guardAdminStream(
    _database.ref('helmets').onValue.map((event) {
      final root = _optionalRecordOf(event.snapshot.value);
      if (root == null) return const <AdminLiveHelmet>[];
      final fleet = <AdminLiveHelmet>[];
      for (final entry in root.entries) {
        final node = _optionalRecordOf(entry.value);
        if (node == null) continue;
        final metaRecord = _optionalRecordOf(node['meta']);
        SensorReading? current;
        var unreadable = false;
        if (node['current'] != null) {
          try {
            current = parseCurrentReadingRecord(node['current'], entry.key);
          } on Object {
            unreadable = true;
          }
        }
        fleet.add(
          AdminLiveHelmet(
            meta: metaRecord == null
                ? HelmetMetaRecord(helmetId: entry.key)
                : HelmetMetaRecord.fromMap(entry.key, metaRecord),
            current: current,
            assessment: _parseAssessment(node['currentAssessment'], entry.key),
            telemetryUnreadable: unreadable,
          ),
        );
      }
      fleet.sort((a, b) => a.helmetId.compareTo(b.helmetId));
      return List<AdminLiveHelmet>.unmodifiable(fleet);
    }),
  );

  @override
  Stream<List<SafetyAlert>> watchRecentAlerts({int limit = 50}) =>
      _guardAdminStream(_fleetAlerts(limit));

  @override
  Stream<bool> watchBackendConnection() => _guardAdminStream(
    _database
        .ref('.info/connected')
        .onValue
        .map((event) => event.snapshot.value == true)
        .distinct(),
  );

  @override
  Stream<AdminOverview> watchOverview() => _combineLatest3(
    watchUsers(),
    watchHelmetsMeta(),
    _watchAlertCounts(),
    (users, helmets, counts) => AdminOverview.from(
      users: users,
      helmets: helmets,
      alertsToday: counts.$1,
      criticalUnacknowledged: counts.$2,
    ),
  );

  @override
  Future<AdminUserAssignments> getUserAssignments(String uid) =>
      _guardAdminRequest(() async {
        final snapshot = await _database.ref('users/$uid').get();
        final record = _optionalRecordOf(snapshot.value);
        if (record == null) return const AdminUserAssignments();
        return AdminUserAssignments.fromMap(record);
      });

  @override
  Future<CreatedUserResult> createUser({
    required String email,
    required String name,
    required UserRole role,
    String? organizationName,
    List<String> siteIds = const [],
  }) async {
    final data = await _call('adminCreateUser', {
      'email': email,
      'name': name,
      'role': role.name,
      if (organizationName != null && organizationName.trim().isNotEmpty)
        'organizationName': organizationName.trim(),
      if (siteIds.isNotEmpty) 'siteIds': siteIds,
    });
    final uid = data['uid']?.toString() ?? '';
    final link = data['passwordSetupLink']?.toString() ?? '';
    if (uid.isEmpty || link.isEmpty) {
      throw const RepositoryAccessException(
        'BACKEND_ERROR',
        'The backend returned an incomplete create-user result.',
      );
    }
    return CreatedUserResult(
      uid: uid,
      user: _userFromResponse(data, uid),
      passwordSetupLink: link,
    );
  }

  @override
  Future<UserProfile> setUserRole({
    required String uid,
    required UserRole role,
  }) async {
    final data = await _call('adminSetUserRole', {
      'uid': uid,
      'role': role.name,
    });
    return _userFromResponse(data, uid);
  }

  @override
  Future<UserProfile> setUserActive({
    required String uid,
    required bool active,
  }) async {
    final data = await _call('adminSetUserActive', {
      'uid': uid,
      'active': active,
    });
    return _userFromResponse(data, uid);
  }

  @override
  Future<UserProfile> updateUserProfile({
    required String uid,
    String? name,
    String? organizationName,
  }) async {
    final data = await _call('adminUpdateUserProfile', {
      'uid': uid,
      'name': ?name,
      'organizationName': ?organizationName,
    });
    return _userFromResponse(data, uid);
  }

  @override
  Future<UserProfile> updateUserAssignments({
    required String uid,
    List<String>? siteIds,
    List<String>? authorizedHelmetIds,
    List<String>? authorizedSupervisorIds,
  }) async {
    final data = await _call('adminUpdateUserAssignments', {
      'uid': uid,
      'siteIds': ?siteIds,
      'authorizedHelmetIds': ?authorizedHelmetIds,
      'authorizedSupervisorIds': ?authorizedSupervisorIds,
    });
    return _userFromResponse(data, uid);
  }

  @override
  Future<void> deleteUser({required String uid}) async {
    await _call('adminDeleteUser', {'uid': uid});
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _guardAdminRequest(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<RegisteredHelmetResult> registerHelmet({
    required String helmetId,
    String? siteId,
    String? label,
  }) async {
    final data = await _call('adminRegisterHelmet', {
      'helmetId': helmetId,
      'siteId': ?siteId,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
    });
    return RegisteredHelmetResult(
      helmet: _helmetFromResponse(data),
      secret: _secretFromResponse(data),
    );
  }

  @override
  Future<HelmetMetaRecord> assignHelmet({
    required String helmetId,
    String? workerUid,
  }) async {
    final data = await _call('adminAssignHelmet', {
      'helmetId': helmetId,
      'workerUid': workerUid,
    });
    return _helmetFromResponse(data);
  }

  @override
  Future<HelmetMetaRecord> setHelmetSite({
    required String helmetId,
    String? siteId,
  }) async {
    final data = await _call('adminSetHelmetSite', {
      'helmetId': helmetId,
      'siteId': siteId,
    });
    return _helmetFromResponse(data);
  }

  @override
  Future<HelmetMetaRecord> retireHelmet({required String helmetId}) async {
    final data = await _call('adminRetireHelmet', {'helmetId': helmetId});
    return _helmetFromResponse(data);
  }

  @override
  Future<HelmetSecretResult> rotateHelmetSecret({
    required String helmetId,
  }) async {
    final data = await _call('adminRotateHelmetSecret', {'helmetId': helmetId});
    return _secretFromResponse(data);
  }

  @override
  Future<Site> upsertSite({
    String? siteId,
    required String name,
    String? description,
  }) async {
    final data = await _call('adminUpsertSite', {
      'siteId': ?siteId,
      'name': name,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
    return _siteFromResponse(data);
  }

  @override
  Future<Site> setSiteSupervisors({
    required String siteId,
    required List<String> supervisorUids,
  }) async {
    final data = await _call('adminSetSiteSupervisors', {
      'siteId': siteId,
      'supervisorUids': supervisorUids,
    });
    return _siteFromResponse(data);
  }

  @override
  Future<HelmetConfiguration> setHelmetThresholds({
    required String helmetId,
    required HelmetConfiguration thresholds,
  }) async {
    final data = await _call('adminSetHelmetThresholds', {
      'helmetId': helmetId,
      'thresholds': {
        'temperatureWarningC': thresholds.temperatureWarningC,
        'temperatureCriticalC': thresholds.temperatureCriticalC,
        'humidityWarningLowPct': thresholds.humidityWarningLowPct,
        'humidityCriticalLowPct': thresholds.humidityCriticalLowPct,
        'humidityWarningHighPct': thresholds.humidityWarningHighPct,
        'humidityCriticalHighPct': thresholds.humidityCriticalHighPct,
        'gasWarningPpm': thresholds.gasWarningPpm,
        'gasCriticalPpm': thresholds.gasCriticalPpm,
        'fallImpactThresholdG': thresholds.fallImpactThresholdG,
        'fallDuplicateCooldownSeconds': thresholds.fallDuplicateCooldownSeconds,
        'normalPollingIntervalSeconds': thresholds.normalPollingIntervalSeconds,
        'gasWarmUpHours': thresholds.gasWarmUpHours,
      },
    });
    final record = _optionalRecordOf(data['thresholds']);
    if (record == null) {
      throw const RepositoryAccessException(
        'BACKEND_ERROR',
        'The backend returned an incomplete thresholds record.',
      );
    }
    final merged = Map<String, dynamic>.of(record);
    merged['helmetId'] ??= helmetId;
    merged['schemaVersion'] ??= currentSchemaVersion;
    merged['configVersion'] ??= thresholds.configVersion;
    merged['updatedBy'] ??= thresholds.updatedBy;
    merged['updatedAt'] ??= thresholds.updatedAt.millisecondsSinceEpoch;
    return HelmetConfiguration.fromJson(merged);
  }
}

/// Demo/mock implementation. Administrative data is never faked: reads are
/// empty and every write throws, so the console can show its
/// "connect a live backend" state instead of inventing records.
final class NoopAdminRepository implements AdminRepository {
  const NoopAdminRepository();

  @override
  bool get isLive => false;

  static const _unsupported = RepositoryAccessException(
    'UNSUPPORTED',
    'Admin actions need a live backend connection.',
  );

  @override
  Stream<List<UserProfile>> watchUsers() => Stream.value(const []);

  @override
  Stream<List<HelmetMetaRecord>> watchHelmetsMeta() => Stream.value(const []);

  @override
  Stream<List<Site>> watchSites() => Stream.value(const []);

  @override
  Stream<HelmetConfiguration?> watchThresholds(String helmetId) =>
      Stream.value(null);

  @override
  Stream<List<AuditLogEntry>> watchAuditLog({int limit = 100}) =>
      Stream.value(const []);

  @override
  Stream<AdminOverview> watchOverview() =>
      Stream.value(AdminOverview.from(users: const [], helmets: const []));

  @override
  Stream<List<AdminLiveHelmet>> watchLiveFleet() => Stream.value(const []);

  @override
  Stream<List<SafetyAlert>> watchRecentAlerts({int limit = 50}) =>
      Stream.value(const []);

  @override
  Stream<bool> watchBackendConnection() => Stream.value(false);

  @override
  Future<AdminUserAssignments> getUserAssignments(String uid) =>
      Future.error(_unsupported);

  @override
  Future<CreatedUserResult> createUser({
    required String email,
    required String name,
    required UserRole role,
    String? organizationName,
    List<String> siteIds = const [],
  }) => Future.error(_unsupported);

  @override
  Future<UserProfile> setUserRole({
    required String uid,
    required UserRole role,
  }) => Future.error(_unsupported);

  @override
  Future<UserProfile> setUserActive({
    required String uid,
    required bool active,
  }) => Future.error(_unsupported);

  @override
  Future<UserProfile> updateUserProfile({
    required String uid,
    String? name,
    String? organizationName,
  }) => Future.error(_unsupported);

  @override
  Future<UserProfile> updateUserAssignments({
    required String uid,
    List<String>? siteIds,
    List<String>? authorizedHelmetIds,
    List<String>? authorizedSupervisorIds,
  }) => Future.error(_unsupported);

  @override
  Future<void> deleteUser({required String uid}) => Future.error(_unsupported);

  @override
  Future<void> sendPasswordReset(String email) => Future.error(_unsupported);

  @override
  Future<RegisteredHelmetResult> registerHelmet({
    required String helmetId,
    String? siteId,
    String? label,
  }) => Future.error(_unsupported);

  @override
  Future<HelmetMetaRecord> assignHelmet({
    required String helmetId,
    String? workerUid,
  }) => Future.error(_unsupported);

  @override
  Future<HelmetMetaRecord> setHelmetSite({
    required String helmetId,
    String? siteId,
  }) => Future.error(_unsupported);

  @override
  Future<HelmetMetaRecord> retireHelmet({required String helmetId}) =>
      Future.error(_unsupported);

  @override
  Future<HelmetSecretResult> rotateHelmetSecret({required String helmetId}) =>
      Future.error(_unsupported);

  @override
  Future<Site> upsertSite({
    String? siteId,
    required String name,
    String? description,
  }) => Future.error(_unsupported);

  @override
  Future<Site> setSiteSupervisors({
    required String siteId,
    required List<String> supervisorUids,
  }) => Future.error(_unsupported);

  @override
  Future<HelmetConfiguration> setHelmetThresholds({
    required String helmetId,
    required HelmetConfiguration thresholds,
  }) => Future.error(_unsupported);
}
