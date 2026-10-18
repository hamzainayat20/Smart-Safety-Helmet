import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../user_role.dart';
import 'dashboard_view_model.dart';

enum HelmetMapState { safe, warning, critical, stale, gpsAcquiring, gpsLost }

final class HelmetMapItem {
  const HelmetMapItem({
    required this.helmet,
    required this.workerName,
    required this.sensorState,
    required this.markerState,
    required this.reading,
    required this.location,
    required this.activeAlert,
  });

  final Helmet helmet;
  final String workerName;
  final MonitoringState sensorState;
  final HelmetMapState markerState;
  final SensorReading? reading;
  final GPSLocation? location;
  final SafetyAlert? activeAlert;

  bool get hasMapPosition => location != null;
  bool get isLastKnown => location?.isLastKnown ?? false;
}

enum MapFocusReason { workerSelection, criticalIncident }

final class MapFocusRequest {
  const MapFocusRequest({
    required this.requestId,
    required this.helmetId,
    required this.location,
    required this.reason,
    required this.zoom,
    this.alertId,
  });

  factory MapFocusRequest.worker({
    required String helmetId,
    required GPSLocation location,
  }) => MapFocusRequest(
    requestId: 'worker:$helmetId:${location.capturedAt.millisecondsSinceEpoch}',
    helmetId: helmetId,
    location: location,
    reason: MapFocusReason.workerSelection,
    zoom: 16,
  );

  factory MapFocusRequest.criticalIncident({
    required String alertId,
    required String helmetId,
    required GPSLocation location,
  }) => MapFocusRequest(
    requestId: 'critical:$alertId',
    alertId: alertId,
    helmetId: helmetId,
    location: location,
    reason: MapFocusReason.criticalIncident,
    zoom: 17,
  );

  final String requestId;
  final String? alertId;
  final String helmetId;
  final GPSLocation location;
  final MapFocusReason reason;
  final double zoom;
}

final class MapFocusController extends ChangeNotifier {
  MapFocusRequest? _current;
  int _revision = 0;

  MapFocusRequest? get current => _current;
  int get revision => _revision;

  void focus(MapFocusRequest request) {
    _current = request;
    _revision += 1;
    notifyListeners();
  }

  void clear() {
    if (_current == null) return;
    _current = null;
    _revision += 1;
    notifyListeners();
  }
}

final class GpsMapViewModel extends ChangeNotifier {
  GpsMapViewModel({
    required this.dashboard,
    DateTime Function()? clock,
    this.gpsStaleAfter = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now {
    dashboard.addListener(_dashboardChanged);
  }

  final DashboardViewModel dashboard;
  final DateTime Function() _clock;
  final Duration gpsStaleAfter;

  UserProfile get profile => dashboard.profile;
  bool get isLoading => dashboard.isLoading;
  bool get permissionDenied =>
      dashboard.loadState == MonitoringState.permissionDenied;
  String? get errorMessage => dashboard.errorMessage;
  String get dataSourceLabel => dashboard.dataSourceLabel;

  List<HelmetMapItem> get items {
    if (!profile.active) return const [];
    final allowedIds = profile.authorizedHelmetIds.toSet();
    final items =
        dashboard.helmets
            .where(
              (helmet) =>
                  helmet.active &&
                  allowedIds.contains(helmet.helmetId) &&
                  _roleCanSeeHelmet(profile.role, helmet),
            )
            .map(_project)
            .toList()
          ..sort((a, b) => a.helmet.helmetId.compareTo(b.helmet.helmetId));
    return List.unmodifiable(items);
  }

  List<HelmetMapItem> get positionedItems =>
      List.unmodifiable(items.where((item) => item.hasMapPosition));

  List<HelmetMapItem> get unpositionedItems =>
      List.unmodifiable(items.where((item) => !item.hasMapPosition));

  HelmetMapItem? itemForHelmet(String helmetId) =>
      items.where((item) => item.helmet.helmetId == helmetId).firstOrNull;

  MapFocusRequest? focusForWorker(String helmetId) {
    final item = itemForHelmet(helmetId);
    final location = item?.location;
    if (item == null || location == null) return null;
    return MapFocusRequest.worker(
      helmetId: item.helmet.helmetId,
      location: location,
    );
  }

  bool _roleCanSeeHelmet(UserRole role, Helmet helmet) => switch (role) {
    UserRole.worker => helmet.assignedWorkerId == profile.uid,
    UserRole.supervisor => profile.siteIds.contains(helmet.siteId),
    UserRole.administrator => true,
  };

  HelmetMapItem _project(Helmet helmet) {
    final reading = dashboard.readingFor(helmet.helmetId);
    final sensorState = dashboard.monitoringStateFor(helmet);
    final activeAlerts =
        dashboard.alerts
            .where(
              (alert) =>
                  alert.helmetId == helmet.helmetId &&
                  alert.status != AlertStatus.resolved,
            )
            .toList()
          ..sort((a, b) => b.serverReceivedAt.compareTo(a.serverReceivedAt));
    return HelmetMapItem(
      helmet: helmet,
      workerName: dashboard.workerNameFor(helmet),
      sensorState: sensorState,
      markerState: _markerState(reading, sensorState),
      reading: reading,
      location: reading?.location,
      activeAlert: activeAlerts.firstOrNull,
    );
  }

  HelmetMapState _markerState(
    SensorReading? reading,
    MonitoringState sensorState,
  ) {
    if (reading == null) return HelmetMapState.gpsAcquiring;
    final location = reading.location;
    if (location == null) {
      return reading.gpsStatus == GpsStatus.acquiring
          ? HelmetMapState.gpsAcquiring
          : HelmetMapState.gpsLost;
    }
    if (location.isLastKnown || reading.gpsStatus != GpsStatus.valid) {
      return HelmetMapState.gpsLost;
    }
    final age = _clock().toUtc().difference(location.capturedAt);
    if (age > gpsStaleAfter || sensorState == MonitoringState.stale) {
      return HelmetMapState.stale;
    }
    return switch (sensorState) {
      MonitoringState.critical ||
      MonitoringState.sensorFault => HelmetMapState.critical,
      MonitoringState.warning ||
      MonitoringState.warmingUp => HelmetMapState.warning,
      MonitoringState.offline => HelmetMapState.stale,
      _ => HelmetMapState.safe,
    };
  }

  void _dashboardChanged() => notifyListeners();

  @override
  void dispose() {
    dashboard.removeListener(_dashboardChanged);
    super.dispose();
  }
}

String helmetMapStateLabel(HelmetMapState state) => switch (state) {
  HelmetMapState.safe => 'Safe',
  HelmetMapState.warning => 'Warning',
  HelmetMapState.critical => 'Critical',
  HelmetMapState.stale => 'Stale',
  HelmetMapState.gpsAcquiring => 'GPS Acquiring',
  HelmetMapState.gpsLost => 'GPS Lost',
};

String helmetMapStateSymbol(HelmetMapState state) => switch (state) {
  HelmetMapState.safe => '✓',
  HelmetMapState.warning => '!',
  HelmetMapState.critical => '!!',
  HelmetMapState.stale => '⌛',
  HelmetMapState.gpsAcquiring => '…',
  HelmetMapState.gpsLost => '×',
};

MapFocusRequest? criticalNotificationMapFocus({
  required UserProfile actor,
  required SafetyAlert alert,
}) {
  final location = alert.location;
  final isAuthorizedSupervisor =
      actor.active &&
      actor.role == UserRole.supervisor &&
      actor.siteIds.contains(alert.siteId) &&
      actor.authorizedHelmetIds.contains(alert.helmetId);
  final hasValidIncidentLocation =
      location != null && !location.isLastKnown && location.hdop != null;
  if (!isAuthorizedSupervisor ||
      alert.severity != SafetySeverity.critical ||
      !hasValidIncidentLocation) {
    return null;
  }
  return MapFocusRequest.criticalIncident(
    alertId: alert.alertId,
    helmetId: alert.helmetId,
    location: location,
  );
}
