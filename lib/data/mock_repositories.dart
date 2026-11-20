import 'dart:async';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../user_role.dart';

final class MockDataSet {
  MockDataSet._({
    required this.users,
    required this.sites,
    required this.helmets,
    required this.readings,
    required this.assessments,
    required this.alerts,
    required this.configurations,
  });

  final Map<String, UserProfile> users;
  final Map<String, Site> sites;
  final Map<String, Helmet> helmets;
  final Map<String, SensorReading> readings;
  final Map<String, SafetyAssessment> assessments;
  final Map<String, SafetyAlert> alerts;
  final Map<String, HelmetConfiguration> configurations;

  factory MockDataSet.currentDemo({DateTime? referenceTimeUtc}) {
    final now = (referenceTimeUtc ?? DateTime.now()).toUtc();
    DateTime ago(Duration duration) => now.subtract(duration);

    final users = <String, UserProfile>{
      'admin-demo': UserProfile(
        uid: 'admin-demo',
        displayName: 'Demo Administrator',
        email: 'admin@example.test',
        role: UserRole.administrator,
        active: true,
        organizationName: 'Smart Safety Demo',
        siteIds: const ['site-main'],
        authorizedHelmetIds: const [
          'H-02',
          'H-03',
          'H-05',
          'H-07',
          'H-09',
          'H-11',
        ],
        updatedAt: now,
      ),
      'supervisor-demo': UserProfile(
        uid: 'supervisor-demo',
        displayName: 'Hamza Inayat',
        email: 'supervisor@example.test',
        role: UserRole.supervisor,
        active: true,
        organizationName: 'Main Site',
        siteIds: const ['site-main'],
        authorizedHelmetIds: const [
          'H-02',
          'H-03',
          'H-05',
          'H-07',
          'H-09',
          'H-11',
        ],
        updatedAt: now,
      ),
      'worker-ali': UserProfile(
        uid: 'worker-ali',
        displayName: 'Ali Shah',
        email: 'worker@example.test',
        role: UserRole.worker,
        active: true,
        organizationName: 'Main Site',
        siteIds: const ['site-main'],
        authorizedHelmetIds: const ['H-03'],
        updatedAt: now,
      ),
      'worker-faisal': UserProfile(
        uid: 'worker-faisal',
        displayName: 'Faisal Khan',
        email: 'faisal@example.test',
        role: UserRole.worker,
        active: true,
        organizationName: 'Main Site',
        siteIds: const ['site-main'],
        authorizedHelmetIds: const ['H-07'],
        updatedAt: now,
      ),
      'worker-zain': UserProfile(
        uid: 'worker-zain',
        displayName: 'Zain Ahmed',
        email: 'zain@example.test',
        role: UserRole.worker,
        active: true,
        organizationName: 'Main Site',
        siteIds: const ['site-main'],
        authorizedHelmetIds: const ['H-11'],
        updatedAt: now,
      ),
      'worker-usman': UserProfile(
        uid: 'worker-usman',
        displayName: 'Usman Baig',
        email: 'usman@example.test',
        role: UserRole.worker,
        active: true,
        organizationName: 'Main Site',
        siteIds: const ['site-main'],
        authorizedHelmetIds: const ['H-02'],
        updatedAt: now,
      ),
      'worker-omar': UserProfile(
        uid: 'worker-omar',
        displayName: 'Omar Farooq',
        email: 'omar@example.test',
        role: UserRole.worker,
        active: true,
        organizationName: 'Main Site',
        siteIds: const ['site-main'],
        authorizedHelmetIds: const ['H-05'],
        updatedAt: now,
      ),
    };

    final sites = <String, Site>{
      'site-main': Site(
        siteId: 'site-main',
        name: 'Main Site',
        organizationName: 'Smart Safety Demo',
        zones: const ['Zone A', 'Zone B', 'Zone C', 'Zone D'],
        active: true,
        updatedAt: now,
      ),
    };

    Helmet helmet(
      String id,
      String workerId,
      String zone, {
      ConnectivityStatus? connectivity,
    }) => Helmet(
      helmetId: id,
      siteId: 'site-main',
      assignedWorkerId: workerId,
      zone: zone,
      firmwareVersion: '1.0.0-demo',
      active: true,
      provisioningStatus: ProvisioningStatus.provisioned,
      connectivity: connectivity ?? ConnectivityStatus.online,
      lastSeenAt: ago(const Duration(seconds: 5)),
      updatedAt: now,
    );

    final helmets = <String, Helmet>{
      'H-02': helmet('H-02', 'worker-usman', 'Zone A'),
      'H-03': helmet('H-03', 'worker-ali', 'Zone A'),
      'H-05': helmet(
        'H-05',
        'worker-omar',
        'Zone A',
        connectivity: ConnectivityStatus.degraded,
      ),
      'H-07': helmet('H-07', 'worker-faisal', 'Zone B'),
      'H-09': Helmet(
        helmetId: 'H-09',
        siteId: 'site-main',
        assignedWorkerId: null,
        zone: 'Zone D',
        firmwareVersion: '1.0.0-demo',
        active: false,
        provisioningStatus: ProvisioningStatus.provisioned,
        connectivity: ConnectivityStatus.offline,
        lastSeenAt: ago(const Duration(hours: 1)),
        updatedAt: now,
      ),
      'H-11': helmet('H-11', 'worker-zain', 'Zone C'),
    };

    SensorReading reading({
      required String helmetId,
      required SafetySeverity severity,
      double? temperatureC,
      double? humidityPct,
      double? gasPpm,
      int? batteryPct,
      GPSLocation? location,
      GpsStatus gpsStatus = GpsStatus.valid,
      ConnectivityStatus connectivity = ConnectivityStatus.online,
      Duration age = const Duration(seconds: 5),
    }) {
      final timestamp = ago(age);
      return SensorReading(
        eventId: 'reading-$helmetId-demo',
        helmetId: helmetId,
        deviceTimestamp: timestamp,
        serverReceivedAt: timestamp.add(const Duration(milliseconds: 300)),
        temperatureC: temperatureC,
        humidityPct: humidityPct,
        gasPpm: gasPpm,
        gasWarmUp: false,
        accelXG: 0.12,
        accelYG: 0.08,
        accelZG: 0.98,
        location: location,
        gpsStatus: gpsStatus,
        batteryPct: batteryPct,
        connectivity: connectivity,
        firmwareVersion: '1.0.0-demo',
        severity: severity,
      );
    }

    GPSLocation location(double lat, double lng, {bool lastKnown = false}) =>
        GPSLocation(
          latitudeDegrees: lat,
          longitudeDegrees: lng,
          hdop: 1.2,
          capturedAt: ago(const Duration(seconds: 8)),
          isLastKnown: lastKnown,
        );

    final readings = <String, SensorReading>{
      'H-02': reading(
        helmetId: 'H-02',
        severity: SafetySeverity.safe,
        temperatureC: 36.5,
        humidityPct: 57,
        gasPpm: 80,
        batteryPct: 73,
        location: location(31.4629, 74.3181),
      ),
      'H-03': reading(
        helmetId: 'H-03',
        severity: SafetySeverity.safe,
        temperatureC: 36.8,
        humidityPct: 58,
        gasPpm: 90,
        batteryPct: 87,
        location: location(31.4628, 74.3183),
      ),
      'H-05': reading(
        helmetId: 'H-05',
        severity: SafetySeverity.warning,
        temperatureC: 37,
        humidityPct: 61,
        gasPpm: 95,
        batteryPct: 18,
        location: location(31.4624, 74.3180, lastKnown: true),
        gpsStatus: GpsStatus.lost,
        connectivity: ConnectivityStatus.degraded,
        age: const Duration(minutes: 22),
      ),
      'H-07': reading(
        helmetId: 'H-07',
        severity: SafetySeverity.warning,
        temperatureC: 42,
        humidityPct: 65,
        gasPpm: 110,
        batteryPct: 45,
        location: location(31.4631, 74.3190),
      ),
      'H-11': reading(
        helmetId: 'H-11',
        severity: SafetySeverity.critical,
        temperatureC: 37.2,
        humidityPct: 62,
        gasPpm: 250,
        batteryPct: 62,
        location: location(31.4619, 74.3175),
      ),
    };

    SafetyAlert alert({
      required String id,
      required String helmetId,
      required String workerId,
      required AlertType type,
      required SafetySeverity severity,
      double? value,
      double? threshold,
      SensorUnit? unit,
      required Duration age,
      AlertStatus status = AlertStatus.delivered,
      String? resolutionNote,
    }) {
      final timestamp = ago(age);
      final numericEvidence = <String, double?>{
        switch (type) {
          AlertType.gas => 'gasPpm',
          AlertType.temperature => 'temperatureC',
          AlertType.humidity => 'humidityPct',
          AlertType.fall => 'impactG',
          AlertType.battery => 'batteryPct',
          AlertType.sensorFault => 'faultCode',
          AlertType.connectivity => 'rssiDbm',
        }: ?value,
        'decisionThreshold': ?threshold,
      };
      if (numericEvidence.isEmpty) {
        numericEvidence['eventConfirmed'] = 1;
      }
      final isResolved = status == AlertStatus.resolved;
      return SafetyAlert(
        alertId: id,
        eventId: 'event-$id',
        helmetId: helmetId,
        siteId: 'site-main',
        workerId: workerId,
        type: type,
        severity: severity,
        sensorValue: value,
        threshold: threshold,
        unit: unit,
        evidence: numericEvidence,
        deviceTimestamp: timestamp,
        serverReceivedAt: timestamp.add(const Duration(milliseconds: 400)),
        location: readings[helmetId]?.location,
        status: status,
        deliveredAt: timestamp.add(const Duration(seconds: 2)),
        acknowledgedBy: isResolved ? 'supervisor-demo' : null,
        acknowledgedAt: isResolved
            ? timestamp.add(const Duration(minutes: 1))
            : null,
        resolvedBy: isResolved ? 'supervisor-demo' : null,
        resolvedAt: isResolved
            ? timestamp.add(const Duration(minutes: 3))
            : null,
        resolutionNote: resolutionNote,
      );
    }

    final alerts = <String, SafetyAlert>{
      'alert-gas-h11': alert(
        id: 'alert-gas-h11',
        helmetId: 'H-11',
        workerId: 'worker-zain',
        type: AlertType.gas,
        severity: SafetySeverity.critical,
        value: 250,
        threshold: 200,
        unit: SensorUnit.partsPerMillion,
        age: const Duration(minutes: 2),
      ),
      'alert-temp-h07': alert(
        id: 'alert-temp-h07',
        helmetId: 'H-07',
        workerId: 'worker-faisal',
        type: AlertType.temperature,
        severity: SafetySeverity.warning,
        value: 42,
        threshold: 40,
        unit: SensorUnit.degreesCelsius,
        age: const Duration(minutes: 7),
      ),
      'alert-battery-h05': alert(
        id: 'alert-battery-h05',
        helmetId: 'H-05',
        workerId: 'worker-omar',
        type: AlertType.battery,
        severity: SafetySeverity.warning,
        value: 18,
        threshold: 20,
        unit: SensorUnit.percent,
        age: const Duration(minutes: 22),
      ),
      'alert-humidity-h03': alert(
        id: 'alert-humidity-h03',
        helmetId: 'H-03',
        workerId: 'worker-ali',
        type: AlertType.humidity,
        severity: SafetySeverity.warning,
        value: 91,
        threshold: 90,
        unit: SensorUnit.percentRelativeHumidity,
        age: const Duration(minutes: 35),
      ),
      'alert-gas-h03-resolved': alert(
        id: 'alert-gas-h03-resolved',
        helmetId: 'H-03',
        workerId: 'worker-ali',
        type: AlertType.gas,
        severity: SafetySeverity.warning,
        value: 150,
        threshold: 100,
        unit: SensorUnit.partsPerMillion,
        age: const Duration(hours: 2),
        status: AlertStatus.resolved,
        resolutionNote: 'Returned to the configured safe range.',
      ),
      'alert-temp-h03-resolved': alert(
        id: 'alert-temp-h03-resolved',
        helmetId: 'H-03',
        workerId: 'worker-ali',
        type: AlertType.temperature,
        severity: SafetySeverity.warning,
        value: 41,
        threshold: 40,
        unit: SensorUnit.degreesCelsius,
        age: const Duration(days: 1),
        status: AlertStatus.resolved,
      ),
    };

    HelmetConfiguration configuration(String helmetId) => HelmetConfiguration(
      helmetId: helmetId,
      configVersion: 'demo-1',
      temperatureWarningC: 40,
      temperatureCriticalC: 50,
      humidityWarningLowPct: 30,
      humidityCriticalLowPct: 20,
      humidityWarningHighPct: 80,
      humidityCriticalHighPct: 90,
      gasWarningPpm: 100,
      gasCriticalPpm: 200,
      fallImpactThresholdG: 2.5,
      fallDuplicateCooldownSeconds: 30,
      normalPollingIntervalSeconds: 5,
      gasWarmUpHours: 24,
      updatedAt: now,
      updatedBy: 'system-demo',
    );

    final assessments = <String, SafetyAssessment>{
      for (final entry in readings.entries)
        entry.key: SafetyAssessment(
          schemaVersion: '1.0',
          assessmentId: entry.value.eventId,
          helmetId: entry.key,
          sourceEventId: entry.value.eventId,
          sourceSchemaVersion: entry.value.schemaVersion,
          deviceTimestamp: entry.value.deviceTimestamp,
          sourceServerReceivedAt: entry.value.serverReceivedAt,
          assessedAt: entry.value.serverReceivedAt.add(
            const Duration(milliseconds: 500),
          ),
          status: InferenceStatus.completed,
          overallRisk: switch (entry.value.severity) {
            SafetySeverity.safe => AssessmentRisk.safe,
            SafetySeverity.warning => AssessmentRisk.warning,
            SafetySeverity.critical => AssessmentRisk.critical,
            SafetySeverity.unassessed => AssessmentRisk.unknown,
          },
          fall: const FallPrediction(
            status: InferenceStatus.completed,
            probability: 0.04,
            threshold: 0.46,
            modelVersion: 'sisfall-kfall-demo',
            inputValid: true,
          ),
          gas: GasPrediction(
            status: entry.value.gasWarmUp
                ? InferenceStatus.unavailable
                : InferenceStatus.completed,
            gasClass: entry.value.gasWarmUp ? GasClass.unknown : GasClass.noGas,
            confidence: entry.value.gasWarmUp ? null : 0.91,
            probabilities: entry.value.gasWarmUp
                ? const {}
                : const {
                    GasClass.mixture: 0.02,
                    GasClass.noGas: 0.91,
                    GasClass.perfume: 0.04,
                    GasClass.smoke: 0.03,
                  },
            modelVersion: 'mq7-mq135-demo',
            inputValid: !entry.value.gasWarmUp,
            outOfDistribution: false,
          ),
          environmentStatus: InferenceStatus.completed,
          temperatureRisk: ComponentRisk.normal,
          humidityRisk: ComponentRisk.normal,
          heatIndexRisk: ComponentRisk.normal,
          reasonCodes: entry.value.gasWarmUp
              ? const ['GAS_SENSOR_WARMING']
              : const ['GAS_NO_GAS'],
          recommendationCodes: entry.value.gasWarmUp
              ? const ['ALLOW_GAS_SENSOR_WARMUP']
              : const ['NO_IMMEDIATE_ACTION'],
          modelBundleVersion: 'phase-a-demo',
        ),
    };

    return MockDataSet._(
      users: users,
      sites: sites,
      helmets: helmets,
      readings: readings,
      assessments: assessments,
      alerts: alerts,
      configurations: {for (final id in helmets.keys) id: configuration(id)},
    );
  }
}

final class MockAuthenticationRepository implements AuthenticationRepository {
  MockAuthenticationRepository(
    this.data, {
    String? initialUid,
    Set<String> unverifiedUids = const {},
    Set<String> disabledUids = const {},
    Set<String> unclaimedUids = const {},
    this.failVerificationEmail = false,
  }) : _unverifiedUids = Set.of(unverifiedUids),
       _disabledUids = Set.of(disabledUids),
       _unclaimedUids = Set.of(unclaimedUids) {
    _current = initialUid == null ? null : _identityFor(initialUid);
  }

  final MockDataSet data;
  final Set<String> _unverifiedUids;
  final Set<String> _disabledUids;
  final Set<String> _unclaimedUids;
  final bool failVerificationEmail;
  final StreamController<AuthenticatedIdentity?> _controller =
      StreamController.broadcast();
  AuthenticatedIdentity? _current;
  int verificationEmailCount = 0;
  int deletedCurrentUserCount = 0;
  final List<String> passwordResetRequests = [];

  AuthenticatedIdentity _identityFor(String uid) {
    final profile = data.users[uid];
    return AuthenticatedIdentity(
      uid: uid,
      email: profile?.email ?? _current?.email,
      emailVerified: !_unverifiedUids.contains(uid),
      trustedRole: _unclaimedUids.contains(uid) ? null : profile?.role,
    );
  }

  @override
  Stream<AuthenticatedIdentity?> get authStateChanges async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<AuthenticatedIdentity> signIn({
    required String email,
    required String password,
  }) async {
    if (password.isEmpty) throw StateError('Password is required');
    final matches = data.users.values.where(
      (profile) => profile.email == email,
    );
    if (matches.isEmpty) {
      throw const AuthFailure(
        AuthFailureCode.invalidCredentials,
        'The email or password is incorrect.',
      );
    }
    final profile = matches.single;
    if (_disabledUids.contains(profile.uid)) {
      throw const AuthFailure(
        AuthFailureCode.disabledAccount,
        'This account has been disabled. Contact an administrator.',
      );
    }
    _current = _identityFor(profile.uid);
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<AuthenticatedIdentity> registerWorker({
    required String email,
    required String password,
  }) async {
    if (password.isEmpty) throw StateError('Password is required');
    final uid = 'worker-${data.users.length + 1}';
    _unverifiedUids.add(uid);
    _current = AuthenticatedIdentity(
      uid: uid,
      email: email,
      emailVerified: false,
    );
    _controller.add(_current);
    return _current!;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (email.trim().isEmpty) {
      throw const AuthFailure(
        AuthFailureCode.invalidEmail,
        'Enter a valid email address.',
      );
    }
    passwordResetRequests.add(email);
  }

  @override
  Future<void> sendEmailVerification() async {
    if (_current == null) {
      throw const AuthFailure(
        AuthFailureCode.noCurrentUser,
        'Sign in before requesting email verification.',
      );
    }
    if (failVerificationEmail) {
      throw const AuthFailure(
        AuthFailureCode.network,
        'Verification email could not be sent.',
      );
    }
    verificationEmailCount++;
  }

  @override
  Future<void> deleteCurrentUser() async {
    final uid = _current?.uid;
    if (uid == null) {
      throw const AuthFailure(
        AuthFailureCode.noCurrentUser,
        'There is no newly created account to remove.',
      );
    }
    deletedCurrentUserCount++;
    data.users.remove(uid);
    _unverifiedUids.remove(uid);
    _current = null;
    _controller.add(null);
  }

  @override
  Future<AuthenticatedIdentity?> refreshIdentity() async {
    final uid = _current?.uid;
    if (uid == null) return null;
    _current = _identityFor(uid);
    _controller.add(_current);
    return _current;
  }

  void markEmailVerified(String uid) => _unverifiedUids.remove(uid);

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}

final class MockUserRepository implements UserRepository {
  MockUserRepository(this.data, {this.failProfileCreation = false});

  final MockDataSet data;
  final bool failProfileCreation;
  final Map<String, StreamController<UserProfile?>> _controllers = {};

  @override
  Future<UserProfile?> getProfile(String uid) async => data.users[uid];

  @override
  Stream<UserProfile?> watchProfile(String uid) async* {
    yield data.users[uid];
    yield* _controllers.putIfAbsent(uid, StreamController.broadcast).stream;
  }

  @override
  Future<void> createWorkerProfile(UserProfile profile) async {
    if (failProfileCreation) {
      throw const RepositoryAccessException(
        'PERMISSION_DENIED',
        'Worker profile creation was denied.',
      );
    }
    if (profile.role != UserRole.worker) {
      throw const RepositoryAccessException(
        'FORBIDDEN_ROLE',
        'Public registration may only create workers.',
      );
    }
    data.users[profile.uid] = profile;
    _controllers[profile.uid]?.add(profile);
  }

  @override
  Future<void> updateNotificationPreferences({
    required UserProfile actor,
    required bool pushAlertsEnabled,
    required bool criticalAlertsOnly,
    required bool vibrationEnabled,
  }) async {
    final current = data.users[actor.uid];
    if (current == null || !current.active) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'User profile is unavailable.',
      );
    }
    final updated = current.copyWith(
      pushAlertsEnabled: pushAlertsEnabled,
      criticalAlertsOnly: criticalAlertsOnly,
      vibrationEnabled: vibrationEnabled,
      updatedAt: DateTime.now().toUtc(),
    );
    data.users[actor.uid] = updated;
    _controllers[actor.uid]?.add(updated);
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
  }
}

final class MockSiteRepository implements SiteRepository {
  MockSiteRepository(this.data);

  final MockDataSet data;

  @override
  Stream<List<Site>> watchAuthorizedSites(UserProfile actor) async* {
    if (actor.role == UserRole.worker) {
      yield const [];
      return;
    }
    final sites =
        data.sites.values
            .where(
              (site) =>
                  actor.role == UserRole.administrator ||
                  actor.siteIds.contains(site.siteId),
            )
            .toList()
          ..sort((a, b) => a.siteId.compareTo(b.siteId));
    yield List.unmodifiable(sites);
  }
}

final class MockHelmetRepository implements HelmetRepository {
  MockHelmetRepository(this.data);

  final MockDataSet data;

  @override
  Future<Helmet?> getAuthorizedHelmet(
    UserProfile actor,
    String helmetId,
  ) async {
    final helmet = data.helmets[helmetId];
    return helmet != null && userCanAccessHelmet(actor, helmet) ? helmet : null;
  }

  @override
  Stream<List<Helmet>> watchAuthorizedHelmets(UserProfile actor) async* {
    final helmets =
        data.helmets.values
            .where((helmet) => userCanAccessHelmet(actor, helmet))
            .toList()
          ..sort((a, b) => a.helmetId.compareTo(b.helmetId));
    yield List.unmodifiable(helmets);
  }
}

final class MockReadingRepository implements ReadingRepository {
  MockReadingRepository(this.data, {this.backendConnected = true});

  final MockDataSet data;
  final bool backendConnected;

  Set<String> _allowedIds(UserProfile actor) => data.helmets.values
      .where((helmet) => userCanAccessHelmet(actor, helmet))
      .map((helmet) => helmet.helmetId)
      .toSet();

  @override
  Stream<bool> watchBackendConnection() => Stream.value(backendConnected);

  @override
  Stream<List<SensorReading>> watchHelmetReadings(
    UserProfile actor,
    String helmetId,
  ) async* {
    if (!_allowedIds(actor).contains(helmetId)) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Helmet reading is outside the assigned scope.',
      );
    }
    final reading = data.readings[helmetId];
    yield reading == null ? const [] : [reading];
  }

  @override
  Stream<Map<String, SensorReading>> watchLatestReadings(
    UserProfile actor,
  ) async* {
    final allowed = _allowedIds(actor);
    yield Map.unmodifiable(
      Map.fromEntries(
        data.readings.entries.where((entry) => allowed.contains(entry.key)),
      ),
    );
  }
}

final class MockAssessmentRepository implements AssessmentRepository {
  MockAssessmentRepository(this.data);

  final MockDataSet data;

  Set<String> _allowedIds(UserProfile actor) => data.helmets.values
      .where((helmet) => userCanAccessHelmet(actor, helmet))
      .map((helmet) => helmet.helmetId)
      .toSet();

  @override
  Stream<Map<String, SafetyAssessment>> watchLatestAssessments(
    UserProfile actor,
  ) async* {
    final allowed = _allowedIds(actor);
    yield Map.unmodifiable(
      Map.fromEntries(
        data.assessments.entries.where((entry) => allowed.contains(entry.key)),
      ),
    );
  }

  @override
  Stream<List<SafetyAssessment>> watchHelmetAssessments(
    UserProfile actor,
    String helmetId,
  ) async* {
    if (!_allowedIds(actor).contains(helmetId)) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Helmet assessments are outside the assigned scope.',
      );
    }
    final assessment = data.assessments[helmetId];
    yield assessment == null ? const [] : [assessment];
  }
}

final class MockAlertRepository implements AlertRepository {
  MockAlertRepository(this.data, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final MockDataSet data;
  final DateTime Function() _clock;
  final StreamController<List<SafetyAlert>> _controller =
      StreamController.broadcast();

  List<SafetyAlert> _authorized(UserProfile actor) {
    final allowedIds = data.helmets.values
        .where((helmet) => userCanAccessHelmet(actor, helmet))
        .map((helmet) => helmet.helmetId)
        .toSet();
    final alerts =
        data.alerts.values
            .where((alert) => allowedIds.contains(alert.helmetId))
            .toList()
          ..sort((a, b) => b.serverReceivedAt.compareTo(a.serverReceivedAt));
    return List.unmodifiable(alerts);
  }

  @override
  Stream<List<SafetyAlert>> watchAuthorizedAlerts(UserProfile actor) async* {
    yield _authorized(actor);
    await for (final _ in _controller.stream) {
      yield _authorized(actor);
    }
  }

  SafetyAlert? _authorizedAlert(UserProfile actor, String alertId) {
    final alert = data.alerts[alertId];
    final helmet = alert == null ? null : data.helmets[alert.helmetId];
    return helmet != null && userCanAccessHelmet(actor, helmet) ? alert : null;
  }

  @override
  Stream<SafetyAlert?> watchAuthorizedAlert(
    UserProfile actor,
    String alertId,
  ) async* {
    yield _authorizedAlert(actor, alertId);
    await for (final _ in _controller.stream) {
      yield _authorizedAlert(actor, alertId);
    }
  }

  @override
  Future<SafetyAlert?> getAuthorizedAlert(
    UserProfile actor,
    String alertId,
  ) async => _authorizedAlert(actor, alertId);

  @override
  Future<SafetyAlert> markViewed({
    required UserProfile actor,
    required String alertId,
  }) async {
    final alert = _authorizedAlert(actor, alertId);
    if (alert == null) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Alert is outside the assigned scope.',
      );
    }
    if (alert.status != AlertStatus.created &&
        alert.status != AlertStatus.delivered) {
      return alert;
    }
    final updated = alert.viewed(actorUid: actor.uid, at: _clock().toUtc());
    data.alerts[alertId] = updated;
    _controller.add(_authorized(actor));
    return updated;
  }

  @override
  Future<SafetyAlert> acknowledge({
    required UserProfile actor,
    required String alertId,
  }) async {
    final alert = data.alerts[alertId];
    final helmet = alert == null ? null : data.helmets[alert.helmetId];
    if (alert == null ||
        helmet == null ||
        !userCanManageHelmet(actor, helmet)) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Alert is outside the supervisor scope.',
      );
    }
    final updated = alert.acknowledged(
      actorUid: actor.uid,
      at: _clock().toUtc(),
    );
    data.alerts[alertId] = updated;
    _controller.add(_authorized(actor));
    return updated;
  }

  @override
  Future<SafetyAlert> resolve({
    required UserProfile actor,
    required String alertId,
    required String resolutionNote,
  }) async {
    final alert = data.alerts[alertId];
    final helmet = alert == null ? null : data.helmets[alert.helmetId];
    final reading = helmet == null ? null : data.readings[helmet.helmetId];
    if (alert == null ||
        helmet == null ||
        !userCanManageHelmet(actor, helmet)) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Alert is outside the supervisor scope.',
      );
    }
    if (alert.status == AlertStatus.resolved) return alert;
    if (alert.status != AlertStatus.acknowledged ||
        reading == null ||
        reading.severity != SafetySeverity.safe ||
        _clock().toUtc().difference(reading.serverReceivedAt) >
            const Duration(seconds: 30)) {
      throw const RepositoryAccessException(
        'HAZARD_ONGOING',
        'The backend cannot confirm that the physical hazard has cleared.',
      );
    }
    final updated = alert.resolved(
      actorUid: actor.uid,
      at: _clock().toUtc(),
      note: resolutionNote,
    );
    data.alerts[alertId] = updated;
    _controller.add(_authorized(actor));
    return updated;
  }

  @override
  Future<SafetyAlert> retryDelivery({
    required UserProfile actor,
    required String alertId,
  }) async {
    final alert = data.alerts[alertId];
    final helmet = alert == null ? null : data.helmets[alert.helmetId];
    if (alert == null ||
        helmet == null ||
        !userCanManageHelmet(actor, helmet)) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Alert is outside the supervisor scope.',
      );
    }
    return alert;
  }

  void dispose() => _controller.close();
}

final class MockConfigurationRepository implements ConfigurationRepository {
  MockConfigurationRepository(this.data);

  final MockDataSet data;

  @override
  Stream<HelmetConfiguration?> watchConfiguration(
    UserProfile actor,
    String helmetId,
  ) async* {
    final helmet = data.helmets[helmetId];
    if (helmet == null || !userCanAccessHelmet(actor, helmet)) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Configuration is outside the assigned scope.',
      );
    }
    yield data.configurations[helmetId];
  }

  @override
  Future<void> updateConfiguration({
    required UserProfile actor,
    required HelmetConfiguration configuration,
  }) async {
    final helmet = data.helmets[configuration.helmetId];
    if (helmet == null || !userCanManageHelmet(actor, helmet)) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Configuration update is not authorized.',
      );
    }
    data.configurations[configuration.helmetId] = configuration;
  }
}

final class MockAssistantRepository implements AssistantRepository {
  @override
  Future<AssistantReply> ask({
    required String helmetId,
    required String question,
  }) async => AssistantReply(
    answer:
        'The current demo assessment is safe. Continue normal monitoring and follow approved site procedures if conditions change.',
    disclaimer:
        'Demo decision-support explanation only; follow approved site procedures.',
    helmetId: helmetId,
    sourceEventId: 'demo-assessment-001',
    generatedAt: DateTime.utc(2026, 1, 1, 12),
  );
}
