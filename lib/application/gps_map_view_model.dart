import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../user_role.dart';
import 'dashboard_view_model.dart';
import 'simulated_gps.dart';

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
    this.phoneLocation,
    this.isSimulatedLocation = false,
  });

  final Helmet helmet;
  final String workerName;
  final MonitoringState sensorState;
  final HelmetMapState markerState;
  final SensorReading? reading;
  final GPSLocation? location;
  final SafetyAlert? activeAlert;
  final WorkerLocation? phoneLocation;

  /// True when [location] is a build-time demo location rather than a fix
  /// reported by helmet hardware.
  final bool isSimulatedLocation;

  bool get hasMapPosition => location != null;
  bool get isLastKnown => location?.isLastKnown ?? false;
  bool get isPhoneLocation => phoneLocation != null;
  bool get phoneLocationIsStale =>
      phoneLocation != null &&
      DateTime.now().toUtc().difference(phoneLocation!.updatedAt) >
          const Duration(minutes: 2);
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
    this.gpsStaleAfter = const Duration(minutes: 2),
    this.simulatedLocations = const DisabledSimulatedLocationProvider(),
  }) : _clock = clock ?? DateTime.now {
    dashboard.addListener(_dashboardChanged);
  }

  final DashboardViewModel dashboard;
  final DateTime Function() _clock;
  final Duration gpsStaleAfter;

  /// Demo locations for helmets without a real fix. Disabled by default.
  final SimulatedLocationProvider simulatedLocations;

  /// True when this build shows demo locations.
  bool get simulationActive => simulatedLocations.isActive;

  /// Why requested simulation was refused (invalid configuration), if so.
  String? get simulationProblem => simulatedLocations.configurationProblem;

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
    if (!simulatedLocations.isActive) return List.unmodifiable(items);
    var simulatedIndex = 0;
    return List.unmodifiable([
      for (final item in items)
        // A real fix always wins. Only helmets that are reporting telemetry
        // but have no location are placed at the demo location.
        if (item.location == null && item.reading != null)
          _withSimulatedLocation(item, simulatedIndex++)
        else
          item,
    ]);
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
    final phoneLocation = dashboard.workerLocationFor(helmet.helmetId);
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
      markerState: phoneLocation == null
          ? _markerState(reading, sensorState)
          : _phoneMarkerState(phoneLocation, sensorState),
      reading: reading,
      location: phoneLocation?.mapLocation ?? reading?.location,
      activeAlert: activeAlerts.firstOrNull,
      phoneLocation: phoneLocation,
    );
  }

  HelmetMapItem _withSimulatedLocation(HelmetMapItem item, int index) {
    final location = simulatedLocations.locationFor(item.helmet, index);
    if (location == null) return item;
    return HelmetMapItem(
      helmet: item.helmet,
      workerName: item.workerName,
      sensorState: item.sensorState,
      markerState: _sensorMarkerState(item.sensorState),
      reading: item.reading,
      location: location,
      activeAlert: item.activeAlert,
      phoneLocation: item.phoneLocation,
      isSimulatedLocation: true,
    );
  }

  // Colour for a positioned helmet, from its real (non-GPS) telemetry state.
  HelmetMapState _sensorMarkerState(MonitoringState sensorState) =>
      switch (sensorState) {
        MonitoringState.critical ||
        MonitoringState.sensorFault => HelmetMapState.critical,
        MonitoringState.warning ||
        MonitoringState.warmingUp => HelmetMapState.warning,
        MonitoringState.stale ||
        MonitoringState.offline => HelmetMapState.stale,
        _ => HelmetMapState.safe,
      };

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

  HelmetMapState _phoneMarkerState(
    WorkerLocation location,
    MonitoringState sensorState,
  ) {
    if (_clock().toUtc().difference(location.updatedAt) > gpsStaleAfter) {
      return HelmetMapState.stale;
    }
    return _sensorMarkerState(sensorState);
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
