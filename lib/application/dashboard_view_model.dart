import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../user_role.dart';
import 'app_dependencies.dart';

final class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required UserProfile profile,
    required this.dependencies,
    DateTime Function()? clock,
    this.staleAfter = const Duration(seconds: 30),
    this.freshnessTick = const Duration(seconds: 5),
  }) : _profile = profile,
       _clock = clock ?? DateTime.now;

  static const Set<String> _requiredSources = {
    'sites',
    'helmets',
    'readings',
    'alerts',
    'connection',
  };

  final AppDependencies dependencies;
  final UserProfile _profile;
  final DateTime Function() _clock;
  final Duration staleAfter;
  final Duration freshnessTick;
  List<Site> _sites = const [];
  List<Helmet> _helmets = const [];
  Map<String, SensorReading> _readings = const {};
  List<SafetyAlert> _alerts = const [];
  Map<String, UserProfile> _workers = const {};
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Set<String> _loadedSources = {};
  Timer? _freshnessTimer;
  RepositoryAccessException? _repositoryError;
  bool? _backendConnected;
  bool _started = false;
  final Set<String> _pendingAcknowledgements = {};

  UserProfile get profile => _profile;
  List<Site> get sites => _sites;
  List<Helmet> get helmets => _helmets;
  Map<String, SensorReading> get readings => _readings;
  List<SafetyAlert> get alerts => _alerts;
  bool? get backendConnected => _backendConnected;
  String? get errorMessage => _repositoryError?.message;
  bool get isLoading =>
      !_requiredSources.every(_loadedSources.contains) &&
      _repositoryError == null;
  bool get isMockData =>
      dependencies.dataSourceKind == DataSourceKind.deterministicMock;
  String get dataSourceLabel => isMockData ? 'Demo data' : 'Live RTDB';
  bool get statisticsAreLive =>
      !isLoading && _repositoryError == null && _backendConnected == true;

  bool isAcknowledging(String alertId) =>
      _pendingAcknowledgements.contains(alertId);

  MonitoringState get loadState {
    if (_repositoryError?.code == 'PERMISSION_DENIED') {
      return MonitoringState.permissionDenied;
    }
    if (_repositoryError != null) return MonitoringState.backendError;
    if (isLoading) return MonitoringState.loading;
    if (_helmets.isEmpty) return MonitoringState.empty;
    return MonitoringState.safe;
  }

  void start() {
    if (_started) return;
    _started = true;
    dependencies.sensitiveData.register(clearSensitiveState);
    _freshnessTimer = Timer.periodic(freshnessTick, (_) => notifyListeners());
    _subscriptions.add(
      dependencies.sites.watchAuthorizedSites(_profile).listen((sites) {
        _sites = sites;
        _markLoaded('sites');
      }, onError: (Object error) => _handleError('sites', error)),
    );
    _subscriptions.add(
      dependencies.helmets.watchAuthorizedHelmets(_profile).listen((
        helmets,
      ) async {
        _helmets = helmets;
        _loadedSources.add('helmets');
        try {
          await _loadWorkers();
        } on Object catch (error) {
          _handleError('workers', error);
          return;
        }
        notifyListeners();
      }, onError: (Object error) => _handleError('helmets', error)),
    );
    _subscriptions.add(
      dependencies.readings.watchLatestReadings(_profile).listen((readings) {
        _readings = readings;
        _markLoaded('readings');
      }, onError: (Object error) => _handleError('readings', error)),
    );
    _subscriptions.add(
      dependencies.alerts.watchAuthorizedAlerts(_profile).listen((alerts) {
        _alerts = alerts;
        _markLoaded('alerts');
      }, onError: (Object error) => _handleError('alerts', error)),
    );
    _subscriptions.add(
      dependencies.readings.watchBackendConnection().listen((connected) {
        _backendConnected = connected;
        _markLoaded('connection');
      }, onError: (Object error) => _handleError('connection', error)),
    );
  }

  void _markLoaded(String source) {
    _loadedSources.add(source);
    notifyListeners();
  }

  Future<void> retry() async {
    await clearSensitiveState();
    start();
  }

  Future<void> clearSensitiveState() async {
    _freshnessTimer?.cancel();
    _freshnessTimer = null;
    final subscriptions = List<StreamSubscription<Object?>>.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    _sites = const [];
    _helmets = const [];
    _readings = const {};
    _alerts = const [];
    _workers = const {};
    _loadedSources.clear();
    _repositoryError = null;
    _backendConnected = null;
    _pendingAcknowledgements.clear();
    _started = false;
    notifyListeners();
  }

  Future<void> _loadWorkers() async {
    final ids = _helmets
        .map((helmet) => helmet.assignedWorkerId)
        .whereType<String>()
        .toSet();
    final entries = await Future.wait(
      ids.map(
        (id) async => MapEntry(id, await dependencies.users.getProfile(id)),
      ),
    );
    _workers = Map.unmodifiable({
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    });
  }

  void _handleError(String source, Object error) {
    _loadedSources.add(source);
    _repositoryError = error is RepositoryAccessException
        ? error
        : const RepositoryAccessException(
            'BACKEND_ERROR',
            'The live monitoring backend is unavailable. Try again.',
          );
    notifyListeners();
  }

  String workerNameFor(Helmet helmet) => helmet.assignedWorkerId == null
      ? 'Unassigned'
      : _workers[helmet.assignedWorkerId]?.displayName ?? 'Assigned worker';

  String siteNameFor(Helmet helmet) =>
      _sites.where((site) => site.siteId == helmet.siteId).firstOrNull?.name ??
      helmet.siteId;

  SensorReading? readingFor(String helmetId) => _readings[helmetId];

  List<Helmet> get activeHelmets =>
      List.unmodifiable(_helmets.where((helmet) => helmet.active));

  int get onlineHelmetCount => activeHelmets.where((helmet) {
    final state = monitoringStateFor(helmet);
    return state == MonitoringState.safe ||
        state == MonitoringState.warning ||
        state == MonitoringState.critical ||
        state == MonitoringState.sensorFault ||
        state == MonitoringState.warmingUp;
  }).length;

  int get activeAlertCount => _alerts
      .where(
        (alert) =>
            alert.status != AlertStatus.acknowledged &&
            alert.status != AlertStatus.resolved,
      )
      .length;

  int get lowBatteryCount => activeHelmets.where((helmet) {
    final reading = readingFor(helmet.helmetId);
    final state = monitoringStateFor(helmet);
    final usable =
        state != MonitoringState.stale &&
        state != MonitoringState.offline &&
        state != MonitoringState.empty;
    return usable && reading?.batteryPct != null && reading!.batteryPct! < 20;
  }).length;

  List<Helmet> get sortedHelmets {
    int rank(Helmet helmet) => switch (monitoringStateFor(helmet)) {
      MonitoringState.critical => 0,
      MonitoringState.sensorFault => 1,
      MonitoringState.warning || MonitoringState.warmingUp => 2,
      MonitoringState.offline => 3,
      MonitoringState.stale => 4,
      MonitoringState.safe => 5,
      _ => 6,
    };

    final result = List<Helmet>.from(_helmets)
      ..sort((a, b) {
        final severity = rank(a).compareTo(rank(b));
        return severity != 0 ? severity : a.helmetId.compareTo(b.helmetId);
      });
    return List.unmodifiable(result);
  }

  bool isStale(SensorReading reading) =>
      _clock().toUtc().difference(reading.serverReceivedAt) > staleAfter;

  MonitoringState monitoringStateFor(Helmet helmet) {
    if (_repositoryError?.code == 'PERMISSION_DENIED') {
      return MonitoringState.permissionDenied;
    }
    if (_repositoryError != null) return MonitoringState.backendError;
    if (isLoading) return MonitoringState.loading;
    final reading = readingFor(helmet.helmetId);
    if (!helmet.active || helmet.connectivity == ConnectivityStatus.offline) {
      return MonitoringState.offline;
    }
    if (reading == null) return MonitoringState.empty;
    if (_backendConnected != true || isStale(reading)) {
      return MonitoringState.stale;
    }
    final hasSensorFaultAlert = _alerts.any(
      (alert) =>
          alert.helmetId == helmet.helmetId &&
          alert.type == AlertType.sensorFault &&
          alert.status != AlertStatus.resolved,
    );
    final hasNoEnvironmentalMeasurement =
        reading.temperatureC == null &&
        reading.humidityPct == null &&
        reading.gasPpm == null;
    final hasActiveSensorReadFailure = reading.sensorFaults.any(
      const {
        SensorFault.mpuReadFailed,
        SensorFault.dhtReadFailed,
        SensorFault.mq7ReadFailed,
      }.contains,
    );
    if (hasSensorFaultAlert ||
        hasActiveSensorReadFailure ||
        hasNoEnvironmentalMeasurement) {
      return MonitoringState.sensorFault;
    }
    if (reading.severity == SafetySeverity.critical) {
      return MonitoringState.critical;
    }
    if (reading.gasWarmUp) return MonitoringState.warmingUp;
    if (reading.severity == SafetySeverity.unassessed) {
      return MonitoringState.sensorFault;
    }
    if (reading.severity == SafetySeverity.warning ||
        reading.connectivity == ConnectivityStatus.degraded ||
        reading.connectivity == ConnectivityStatus.offlineBuffering) {
      return MonitoringState.warning;
    }
    return MonitoringState.safe;
  }

  String stateLabelFor(Helmet helmet) => switch (monitoringStateFor(helmet)) {
    MonitoringState.loading => 'Loading',
    MonitoringState.empty => 'No Data',
    MonitoringState.safe => 'Safe',
    MonitoringState.warning => 'Warning',
    MonitoringState.critical => 'Critical',
    MonitoringState.stale => 'Stale',
    MonitoringState.offline => 'Offline',
    MonitoringState.sensorFault => 'Sensor Fault',
    MonitoringState.warmingUp => 'Warming Up',
    MonitoringState.permissionDenied => 'Permission Denied',
    MonitoringState.backendError => 'Backend Error',
  };

  DateTime? lastUpdateFor(Helmet helmet) =>
      readingFor(helmet.helmetId)?.serverReceivedAt ?? helmet.lastSeenAt;

  bool hasActiveAlert(String helmetId, AlertType type) => _alerts.any(
    (alert) =>
        alert.helmetId == helmetId &&
        alert.type == type &&
        alert.status != AlertStatus.resolved,
  );

  Future<void> acknowledge(String alertId) async {
    if (_profile.role != UserRole.supervisor &&
        _profile.role != UserRole.administrator) {
      throw const RepositoryAccessException(
        'FORBIDDEN_SCOPE',
        'Workers cannot acknowledge alerts.',
      );
    }
    if (!_pendingAcknowledgements.add(alertId)) return;
    notifyListeners();
    try {
      await dependencies.alerts.acknowledge(actor: _profile, alertId: alertId);
    } finally {
      _pendingAcknowledgements.remove(alertId);
      notifyListeners();
    }
  }

  Future<void> updateNotificationPreferences({
    bool? pushAlertsEnabled,
    bool? criticalAlertsOnly,
    bool? vibrationEnabled,
  }) => dependencies.users.updateNotificationPreferences(
    actor: _profile,
    pushAlertsEnabled: pushAlertsEnabled ?? _profile.pushAlertsEnabled,
    criticalAlertsOnly: criticalAlertsOnly ?? _profile.criticalAlertsOnly,
    vibrationEnabled: vibrationEnabled ?? _profile.vibrationEnabled,
  );

  @override
  void dispose() {
    dependencies.sensitiveData.unregister(clearSensitiveState);
    _freshnessTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}
