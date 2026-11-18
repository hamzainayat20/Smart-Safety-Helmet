import '../domain/models.dart';

// Compile-time switches. Simulated GPS is OFF unless a build explicitly passes
// --dart-define=SMART_SAFETY_ENABLE_SIMULATED_GPS=true together with an
// approved public test coordinate. Nothing here reads browser location.
const bool _simulationRequested = bool.fromEnvironment(
  'SMART_SAFETY_ENABLE_SIMULATED_GPS',
);
const String _simulatedLatitude = String.fromEnvironment(
  'SMART_SAFETY_SIMULATED_LAT',
);
const String _simulatedLongitude = String.fromEnvironment(
  'SMART_SAFETY_SIMULATED_LNG',
);

/// Validated simulated-GPS build configuration.
final class SimulatedGpsConfig {
  const SimulatedGpsConfig._({
    required this.requested,
    this.latitude,
    this.longitude,
    this.problem,
  });

  /// Default for every build that does not opt in.
  static const disabled = SimulatedGpsConfig._(requested: false);

  /// Parses the raw dart-define values. An enabled flag with a missing or
  /// invalid coordinate never produces a location; it reports [problem].
  factory SimulatedGpsConfig.parse({
    required bool enabled,
    required String latitude,
    required String longitude,
  }) {
    if (!enabled) return disabled;
    final lat = double.tryParse(latitude.trim());
    final lng = double.tryParse(longitude.trim());
    final String? problem;
    if (lat == null || lng == null) {
      problem =
          'SMART_SAFETY_SIMULATED_LAT and SMART_SAFETY_SIMULATED_LNG must '
          'both be numbers.';
    } else if (!lat.isFinite || !lng.isFinite) {
      problem = 'Simulated coordinates must be finite numbers.';
    } else if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      problem = 'Simulated coordinates are outside the valid range.';
    } else if (lat == 0 && lng == 0) {
      problem = '0,0 is an invalid GPS sentinel, not a location.';
    } else {
      problem = null;
    }
    return problem == null
        ? SimulatedGpsConfig._(requested: true, latitude: lat, longitude: lng)
        : SimulatedGpsConfig._(requested: true, problem: problem);
  }

  /// Reads the compile-time dart-defines of this build.
  factory SimulatedGpsConfig.fromEnvironment() => SimulatedGpsConfig.parse(
    enabled: _simulationRequested,
    latitude: _simulatedLatitude,
    longitude: _simulatedLongitude,
  );

  final bool requested;
  final double? latitude;
  final double? longitude;
  final String? problem;

  bool get active => requested && problem == null;
}

/// Supplies demonstration locations for helmets that have no real GPS fix.
///
/// Simulated locations exist only in the app's map presentation. They are
/// never written to Firebase, never attached to a [SensorReading] and never
/// replace a real fix.
abstract interface class SimulatedLocationProvider {
  /// True when demo locations will be produced.
  bool get isActive;

  /// Set when simulation was requested but its configuration is invalid.
  String? get configurationProblem;

  /// Demo location for the [index]-th helmet lacking a real fix, or null.
  GPSLocation? locationFor(Helmet helmet, int index);
}

/// Default: no simulation. Production builds use this.
final class DisabledSimulatedLocationProvider
    implements SimulatedLocationProvider {
  const DisabledSimulatedLocationProvider();

  @override
  bool get isActive => false;

  @override
  String? get configurationProblem => null;

  @override
  GPSLocation? locationFor(Helmet helmet, int index) => null;
}

/// One fixed, approved public test coordinate. Additional helmets are offset
/// by about 17 m each so markers do not overlap.
final class StaticSimulatedLocationProvider
    implements SimulatedLocationProvider {
  StaticSimulatedLocationProvider(this.config, {DateTime Function()? clock})
    : _createdAt = (clock ?? DateTime.now)().toUtc();

  static const double _offsetDegrees = 0.00015;

  final SimulatedGpsConfig config;

  // Fixed at start-up: a simulated position never pretends to be a fresh fix.
  final DateTime _createdAt;

  @override
  bool get isActive => config.active;

  @override
  String? get configurationProblem => config.problem;

  @override
  GPSLocation? locationFor(Helmet helmet, int index) {
    if (!config.active || index < 0) return null;
    final latitude = config.latitude! + index * _offsetDegrees;
    if (latitude > 90) return null;
    return GPSLocation(
      latitudeDegrees: latitude,
      longitudeDegrees: config.longitude!,
      capturedAt: _createdAt,
      isLastKnown: false,
    );
  }
}

/// Provider for this build's dart-defines (disabled unless opted in).
SimulatedLocationProvider simulatedLocationProviderFromEnvironment() {
  final config = SimulatedGpsConfig.fromEnvironment();
  return config.requested
      ? StaticSimulatedLocationProvider(config)
      : const DisabledSimulatedLocationProvider();
}
