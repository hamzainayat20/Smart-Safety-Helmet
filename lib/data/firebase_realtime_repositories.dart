import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../user_role.dart';
import 'sensor_reading_ingestion.dart';

abstract final class RealtimeDatabasePaths {
  static String user(String uid) => 'users/$uid';
  static String site(String siteId) => 'sites/$siteId';
  static String helmetMeta(String helmetId) => 'helmets/$helmetId/meta';
  static String helmetCurrent(String helmetId) => 'helmets/$helmetId/current';
  static String helmetReadings(String helmetId) => 'readings/$helmetId';
  static const String alerts = 'alerts';
  static const String configDefaults = 'config/defaults';
  static String helmetConfig(String helmetId) => 'config/helmets/$helmetId';
  static const String connection = '.info/connected';
}

Map<String, dynamic> _record(Object? value, String path) {
  if (value is! Map) {
    throw ModelValidationException('$path must contain an object');
  }
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}

Map<String, dynamic>? _optionalRecord(Object? value, String path) {
  if (value == null) return null;
  return _record(value, path);
}

RepositoryAccessException _databaseFailure(Object error) {
  if (error is RepositoryAccessException) return error;
  if (error is FirebaseException &&
      (error.code == 'permission-denied' ||
          error.code == 'permission_denied')) {
    return const RepositoryAccessException(
      'PERMISSION_DENIED',
      'Permission denied for the requested monitoring data.',
    );
  }
  if (error is FirebaseFunctionsException) {
    final code = switch (error.code) {
      'permission-denied' || 'unauthenticated' => 'PERMISSION_DENIED',
      'failed-precondition' => 'HAZARD_ONGOING',
      'not-found' => 'NOT_FOUND',
      _ => 'BACKEND_ERROR',
    };
    return RepositoryAccessException(
      code,
      error.message ?? 'The alert operation could not be completed.',
    );
  }
  return const RepositoryAccessException(
    'BACKEND_ERROR',
    'The live monitoring backend is unavailable. Try again.',
  );
}

Stream<T> _guardStream<T>(Stream<T> source) async* {
  try {
    yield* source;
  } on Object catch (error) {
    throw _databaseFailure(error);
  }
}

Future<T> _guardRequest<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on Object catch (error) {
    throw _databaseFailure(error);
  }
}

List<String> _authorizedHelmetIds(UserProfile actor) {
  if (!actor.active) return const [];
  final ids = actor.authorizedHelmetIds.toSet().toList()..sort();
  return List.unmodifiable(ids);
}

Stream<Map<String, T>> _combineByKey<T>(Map<String, Stream<T?>> sources) {
  late StreamController<Map<String, T>> controller;
  final subscriptions = <StreamSubscription<T?>>[];
  final values = <String, T>{};
  final loaded = <String>{};

  void emit() {
    if (!controller.isClosed && loaded.length == sources.length) {
      controller.add(Map.unmodifiable(values));
    }
  }

  controller = StreamController<Map<String, T>>(
    sync: true,
    onListen: () {
      if (sources.isEmpty) {
        controller.add(const {});
        return;
      }
      for (final entry in sources.entries) {
        subscriptions.add(
          entry.value.listen((value) {
            loaded.add(entry.key);
            if (value == null) {
              values.remove(entry.key);
            } else {
              values[entry.key] = value;
            }
            emit();
          }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    },
  );
  return controller.stream;
}

final class RtdbUserRepository implements UserRepository {
  RtdbUserRepository({FirebaseDatabase? database})
    : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  UserProfile? _parse(DataSnapshot snapshot, String uid) {
    final data = _optionalRecord(
      snapshot.value,
      RealtimeDatabasePaths.user(uid),
    );
    if (data == null) return null;
    data['uid'] ??= uid;
    data['schemaVersion'] ??= currentSchemaVersion;
    data['updatedAt'] ??= 0;
    return UserProfile.fromJson(data);
  }

  @override
  Future<UserProfile?> getProfile(String uid) => _guardRequest(() async {
    final snapshot = await _database.ref(RealtimeDatabasePaths.user(uid)).get();
    return _parse(snapshot, uid);
  });

  @override
  Stream<UserProfile?> watchProfile(String uid) => _guardStream(
    _database
        .ref(RealtimeDatabasePaths.user(uid))
        .onValue
        .map((event) => _parse(event.snapshot, uid)),
  );

  @override
  Future<void> createWorkerProfile(UserProfile profile) =>
      _guardRequest(() async {
        if (profile.role != UserRole.worker ||
            profile.siteIds.isNotEmpty ||
            profile.authorizedHelmetIds.isNotEmpty) {
          throw const RepositoryAccessException(
            'FORBIDDEN_ROLE',
            'Public registration may only create an unassigned worker.',
          );
        }
        final data = profile.toJson()
          ..['name'] = profile.displayName
          ..remove('displayName')
          ..['siteIds'] = const <String, bool>{}
          ..['authorizedHelmetIds'] = const <String, bool>{}
          ..['updatedAt'] = ServerValue.timestamp;
        await _database.ref(RealtimeDatabasePaths.user(profile.uid)).set(data);
      });

  @override
  Future<void> updateNotificationPreferences({
    required UserProfile actor,
    required bool pushAlertsEnabled,
    required bool criticalAlertsOnly,
    required bool vibrationEnabled,
  }) => _guardRequest(() async {
    await _database.ref(RealtimeDatabasePaths.user(actor.uid)).update({
      'pushAlertsEnabled': pushAlertsEnabled,
      'criticalAlertsOnly': criticalAlertsOnly,
      'vibrationEnabled': vibrationEnabled,
      'updatedAt': ServerValue.timestamp,
    });
  });
}

final class RtdbSiteRepository implements SiteRepository {
  RtdbSiteRepository({FirebaseDatabase? database})
    : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  @override
  Stream<List<Site>> watchAuthorizedSites(UserProfile actor) {
    if (actor.role == UserRole.worker || !actor.active) {
      return Stream.value(const []);
    }
    final sources = <String, Stream<Site?>>{
      for (final siteId in actor.siteIds.toSet())
        siteId: _guardStream(
          _database.ref(RealtimeDatabasePaths.site(siteId)).onValue.map((
            event,
          ) {
            final data = _optionalRecord(
              event.snapshot.value,
              RealtimeDatabasePaths.site(siteId),
            );
            if (data == null) return null;
            data['siteId'] ??= siteId;
            data['schemaVersion'] ??= currentSchemaVersion;
            return Site.fromJson(data);
          }),
        ),
    };
    return _combineByKey(sources).map((items) {
      final result = items.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return List<Site>.unmodifiable(result);
    });
  }
}

final class RtdbHelmetRepository implements HelmetRepository {
  RtdbHelmetRepository({FirebaseDatabase? database})
    : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  Helmet? _parse(DataSnapshot snapshot, String helmetId) {
    final data = _optionalRecord(
      snapshot.value,
      RealtimeDatabasePaths.helmetMeta(helmetId),
    );
    if (data == null) return null;
    data['helmetId'] ??= helmetId;
    data['schemaVersion'] ??= currentSchemaVersion;
    if (data['lastSeenAt'] == null && data['lastSeen'] != null) {
      data['lastSeenAt'] = data['lastSeen'];
    }
    return Helmet.fromJson(data);
  }

  @override
  Stream<List<Helmet>> watchAuthorizedHelmets(UserProfile actor) {
    final sources = <String, Stream<Helmet?>>{
      for (final helmetId in _authorizedHelmetIds(actor))
        helmetId: _guardStream(
          _database
              .ref(RealtimeDatabasePaths.helmetMeta(helmetId))
              .onValue
              .map((event) => _parse(event.snapshot, helmetId)),
        ),
    };
    return _combineByKey(sources).map((items) {
      final result =
          items.values
              .where((helmet) => userCanAccessHelmet(actor, helmet))
              .toList()
            ..sort((a, b) => a.helmetId.compareTo(b.helmetId));
      return List<Helmet>.unmodifiable(result);
    });
  }

  @override
  Future<Helmet?> getAuthorizedHelmet(UserProfile actor, String helmetId) =>
      _guardRequest(() async {
        if (!_authorizedHelmetIds(actor).contains(helmetId)) return null;
        final snapshot = await _database
            .ref(RealtimeDatabasePaths.helmetMeta(helmetId))
            .get();
        final helmet = _parse(snapshot, helmetId);
        return helmet != null && userCanAccessHelmet(actor, helmet)
            ? helmet
            : null;
      });
}

final class RtdbReadingRepository implements ReadingRepository {
  RtdbReadingRepository({FirebaseDatabase? database, this.historyLimit = 100})
    : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;
  final int historyLimit;

  SensorReading? _parseCurrent(DataSnapshot snapshot, String helmetId) {
    final data = _optionalRecord(
      snapshot.value,
      RealtimeDatabasePaths.helmetCurrent(helmetId),
    );
    if (data == null) return null;
    data['helmetId'] ??= helmetId;
    data['schemaVersion'] ??= currentSchemaVersion;
    return SensorReading.fromJson(normalizeSensorReadingAtIngestion(data));
  }

  @override
  Stream<bool> watchBackendConnection() => _guardStream(
    _database
        .ref(RealtimeDatabasePaths.connection)
        .onValue
        .map((event) => event.snapshot.value == true)
        .distinct(),
  );

  @override
  Stream<Map<String, SensorReading>> watchLatestReadings(UserProfile actor) {
    final sources = <String, Stream<SensorReading?>>{
      for (final helmetId in _authorizedHelmetIds(actor))
        helmetId: _guardStream(
          _database
              .ref(RealtimeDatabasePaths.helmetCurrent(helmetId))
              .onValue
              .map((event) => _parseCurrent(event.snapshot, helmetId)),
        ),
    };
    return _combineByKey(sources);
  }

  @override
  Stream<List<SensorReading>> watchHelmetReadings(
    UserProfile actor,
    String helmetId,
  ) {
    if (!_authorizedHelmetIds(actor).contains(helmetId)) {
      return Stream.error(
        const RepositoryAccessException(
          'FORBIDDEN_SCOPE',
          'Helmet readings are outside the assigned scope.',
        ),
      );
    }
    final query = _database
        .ref(RealtimeDatabasePaths.helmetReadings(helmetId))
        .orderByChild('serverReceivedAt')
        .limitToLast(historyLimit);
    return _guardStream(
      query.onValue.map((event) {
        final records = _optionalRecord(
          event.snapshot.value,
          RealtimeDatabasePaths.helmetReadings(helmetId),
        );
        if (records == null) return const <SensorReading>[];
        final readings = <SensorReading>[];
        for (final entry in records.entries) {
          final data = _record(
            entry.value,
            '${RealtimeDatabasePaths.helmetReadings(helmetId)}/${entry.key}',
          );
          data['eventId'] ??= entry.key;
          data['helmetId'] ??= helmetId;
          data['schemaVersion'] ??= currentSchemaVersion;
          readings.add(
            SensorReading.fromJson(normalizeSensorReadingAtIngestion(data)),
          );
        }
        readings.sort(
          (a, b) => b.serverReceivedAt.compareTo(a.serverReceivedAt),
        );
        return List<SensorReading>.unmodifiable(readings);
      }),
    );
  }
}

final class RtdbAlertRepository implements AlertRepository {
  RtdbAlertRepository({
    FirebaseDatabase? database,
    FirebaseFunctions? functions,
    this.alertLimitPerHelmet = 100,
  }) : _database = database ?? FirebaseDatabase.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseDatabase _database;
  final FirebaseFunctions _functions;
  final int alertLimitPerHelmet;

  Stream<Map<String, SafetyAlert>> _watchHelmetAlerts(String helmetId) {
    final query = _database
        .ref(RealtimeDatabasePaths.alerts)
        .orderByChild('helmetId')
        .equalTo(helmetId)
        .limitToLast(alertLimitPerHelmet);
    return _guardStream(
      query.onValue.map((event) {
        final records = _optionalRecord(
          event.snapshot.value,
          RealtimeDatabasePaths.alerts,
        );
        if (records == null) return const <String, SafetyAlert>{};
        return Map.unmodifiable({
          for (final entry in records.entries)
            entry.key: SafetyAlert.fromJson(
              _record(entry.value, 'alerts/${entry.key}')
                ..putIfAbsent('alertId', () => entry.key)
                ..putIfAbsent('schemaVersion', () => currentSchemaVersion),
            ),
        });
      }),
    );
  }

  @override
  Stream<List<SafetyAlert>> watchAuthorizedAlerts(UserProfile actor) {
    final sources = <String, Stream<Map<String, SafetyAlert>?>>{
      for (final helmetId in _authorizedHelmetIds(actor))
        helmetId: _watchHelmetAlerts(helmetId),
    };
    return _combineByKey(sources).map((byHelmet) {
      final alerts = byHelmet.values.expand((items) => items.values).toList()
        ..sort((a, b) => b.serverReceivedAt.compareTo(a.serverReceivedAt));
      return List<SafetyAlert>.unmodifiable(alerts);
    });
  }

  SafetyAlert _parseAlertValue(Object? value, String alertId) {
    final data = _record(value, 'alerts/$alertId')
      ..putIfAbsent('alertId', () => alertId)
      ..putIfAbsent('schemaVersion', () => currentSchemaVersion);
    return SafetyAlert.fromJson(data);
  }

  SafetyAlert _parseCallableAlert(Object? value, String operation) {
    if (value is! Map) {
      throw RepositoryAccessException(
        'BACKEND_ERROR',
        '$operation returned an invalid response.',
      );
    }
    final result = Map<String, dynamic>.from(value);
    final alert = result['alert'];
    if (alert is! Map) {
      throw RepositoryAccessException(
        'BACKEND_ERROR',
        '$operation did not return the canonical alert.',
      );
    }
    return SafetyAlert.fromJson(Map<String, dynamic>.from(alert));
  }

  @override
  Stream<SafetyAlert?> watchAuthorizedAlert(UserProfile actor, String alertId) {
    if (alertId.trim().isEmpty || !actor.active) {
      return Stream.error(
        const RepositoryAccessException(
          'FORBIDDEN_SCOPE',
          'The alert is outside the assigned scope.',
        ),
      );
    }
    final reference = _database.ref('${RealtimeDatabasePaths.alerts}/$alertId');
    return _guardStream(
      reference.onValue.map((event) {
        if (!event.snapshot.exists) return null;
        final alert = _parseAlertValue(event.snapshot.value, alertId);
        if (actor.role != UserRole.administrator &&
            !actor.authorizedHelmetIds.contains(alert.helmetId)) {
          throw const RepositoryAccessException(
            'FORBIDDEN_SCOPE',
            'The alert is outside the assigned scope.',
          );
        }
        return alert;
      }),
    );
  }

  @override
  Future<SafetyAlert?> getAuthorizedAlert(UserProfile actor, String alertId) =>
      _guardRequest(() async {
        final snapshot = await _database
            .ref('${RealtimeDatabasePaths.alerts}/$alertId')
            .get();
        if (!snapshot.exists) return null;
        return _parseAlertValue(snapshot.value, alertId);
      });

  Future<SafetyAlert> _callAlertOperation(
    String functionName,
    String label,
    Map<String, Object?> data,
  ) => _guardRequest(() async {
    final response = await _functions.httpsCallable(functionName).call(data);
    return _parseCallableAlert(response.data, label);
  });

  @override
  Future<SafetyAlert> markViewed({
    required UserProfile actor,
    required String alertId,
  }) => _callAlertOperation('markAlertViewed', 'Mark viewed', {
    'alertId': alertId,
  });

  @override
  Future<SafetyAlert> acknowledge({
    required UserProfile actor,
    required String alertId,
  }) {
    if (actor.role != UserRole.supervisor &&
        actor.role != UserRole.administrator) {
      return Future.error(
        const RepositoryAccessException(
          'FORBIDDEN_SCOPE',
          'Only an authorized supervisor can acknowledge an alert.',
        ),
      );
    }
    return _callAlertOperation('acknowledgeAlert', 'Acknowledge', {
      'alertId': alertId,
    });
  }

  @override
  Future<SafetyAlert> resolve({
    required UserProfile actor,
    required String alertId,
    required String resolutionNote,
  }) => _callAlertOperation('resolveAlert', 'Resolve', {
    'alertId': alertId,
    'resolutionNote': resolutionNote,
  });

  @override
  Future<SafetyAlert> retryDelivery({
    required UserProfile actor,
    required String alertId,
  }) => _callAlertOperation('retryAlertDelivery', 'Retry delivery', {
    'alertId': alertId,
  });
}

final class RtdbConfigurationRepository implements ConfigurationRepository {
  RtdbConfigurationRepository({FirebaseDatabase? database})
    : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  @override
  Stream<HelmetConfiguration?> watchConfiguration(
    UserProfile actor,
    String helmetId,
  ) {
    if (!_authorizedHelmetIds(actor).contains(helmetId)) {
      return Stream.error(
        const RepositoryAccessException(
          'FORBIDDEN_SCOPE',
          'Helmet configuration is outside the assigned scope.',
        ),
      );
    }
    final sources = <String, Stream<Map<String, dynamic>?>>{
      'defaults': _guardStream(
        _database
            .ref(RealtimeDatabasePaths.configDefaults)
            .onValue
            .map(
              (event) => _optionalRecord(
                event.snapshot.value,
                RealtimeDatabasePaths.configDefaults,
              ),
            ),
      ),
      'helmet': _guardStream(
        _database
            .ref(RealtimeDatabasePaths.helmetConfig(helmetId))
            .onValue
            .map(
              (event) => _optionalRecord(
                event.snapshot.value,
                RealtimeDatabasePaths.helmetConfig(helmetId),
              ),
            ),
      ),
    };
    return _combineByKey(sources).map((records) {
      final defaults = records['defaults'];
      if (defaults == null) return null;
      final merged = <String, dynamic>{
        ...defaults,
        ...?records['helmet'],
        'helmetId': helmetId,
      };
      merged['schemaVersion'] ??= currentSchemaVersion;
      merged['updatedBy'] ??= 'system-default';
      return HelmetConfiguration.fromJson(merged);
    });
  }

  @override
  Future<void> updateConfiguration({
    required UserProfile actor,
    required HelmetConfiguration configuration,
  }) => _guardRequest(() async {
    if (!actor.authorizedHelmetIds.contains(configuration.helmetId)) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Helmet configuration is outside the assigned scope.',
      );
    }
    final data = configuration.toJson()
      ..['updatedBy'] = actor.uid
      ..['updatedAt'] = ServerValue.timestamp;
    await _database
        .ref(RealtimeDatabasePaths.helmetConfig(configuration.helmetId))
        .set(data);
  });
}
