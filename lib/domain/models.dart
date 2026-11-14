import 'dart:collection';

import '../user_role.dart';

const String currentSchemaVersion = '1.0';

final class ModelValidationException implements FormatException {
  ModelValidationException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final dynamic source;

  @override
  final int? offset;

  @override
  String toString() => 'ModelValidationException: $message';
}

final class AssistantReply {
  const AssistantReply({
    required this.answer,
    required this.disclaimer,
    required this.helmetId,
    required this.sourceEventId,
    required this.generatedAt,
  });

  final String answer;
  final String disclaimer;
  final String helmetId;
  final String sourceEventId;
  final DateTime generatedAt;
}

enum SafetySeverity { unassessed, safe, warning, critical }

enum InferenceStatus {
  pending,
  completed,
  unavailable,
  outOfDistribution,
  error,
}

enum GasClass { mixture, noGas, perfume, smoke, unknown }

enum AssessmentRisk { unknown, safe, warning, critical }

enum ComponentRisk { normal, warning, critical, unavailable }

enum MonitoringState {
  loading,
  empty,
  safe,
  warning,
  critical,
  stale,
  offline,
  sensorFault,
  warmingUp,
  permissionDenied,
  backendError,
}

enum ConnectivityStatus { online, degraded, offlineBuffering, offline }

enum GpsStatus { acquiring, valid, lost, invalid }

enum FallStatus {
  notEvaluated,
  normal,
  freeFallCandidate,
  impactDetected,
  stillnessCandidate,
  confirmed,
  cooldown,
}

enum SensorFault {
  mpuReadFailed,
  dhtReadFailed,
  mq7ReadFailed,
  mq7Uncalibrated,
  mq7HeaterStateUnknown,
  gpsUnavailable,
  batteryUnavailable,
}

enum ProvisioningStatus { unprovisioned, provisioned, revoked }

enum AlertType {
  gas,
  temperature,
  humidity,
  fall,
  battery,
  sensorFault,
  connectivity,
}

enum AlertStatus { created, delivered, viewed, acknowledged, resolved }

enum SensorUnit {
  degreesCelsius('°C'),
  percentRelativeHumidity('% RH'),
  partsPerMillion('ppm'),
  percent('%'),
  standardGravity('g'),
  decibelMilliwatts('dBm');

  const SensorUnit(this.symbol);

  final String symbol;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw ModelValidationException('$key must be a non-empty string', json);
  }
  return value.trim();
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw ModelValidationException(
      '$key must be null or a non-empty string',
      json,
    );
  }
  return value.trim();
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw ModelValidationException('$key must be a boolean', json);
  }
  return value;
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! bool) {
    throw ModelValidationException('$key must be a boolean', json);
  }
  return value;
}

double? _optionalNumber(
  Map<String, dynamic> json,
  String key, {
  double? min,
  double? max,
}) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw ModelValidationException('$key must be a finite number', json);
  }
  final result = value.toDouble();
  if (min != null && result < min || max != null && result > max) {
    throw ModelValidationException('$key is outside the allowed range', json);
  }
  return result;
}

double _requiredNumber(
  Map<String, dynamic> json,
  String key, {
  double? min,
  double? max,
}) {
  final value = _optionalNumber(json, key, min: min, max: max);
  if (value == null) {
    throw ModelValidationException('$key is required', json);
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key, {int? min, int? max}) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite || value.toInt() != value) {
    throw ModelValidationException('$key must be an integer', json);
  }
  final result = value.toInt();
  if (min != null && result < min || max != null && result > max) {
    throw ModelValidationException('$key is outside the allowed range', json);
  }
  return result;
}

DateTime _requiredTimestamp(Map<String, dynamic> json, String key) {
  final milliseconds = _optionalInt(json, key, min: 0);
  if (milliseconds == null) {
    throw ModelValidationException('$key is required', json);
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

DateTime? _optionalTimestamp(Map<String, dynamic> json, String key) {
  final milliseconds = _optionalInt(json, key, min: 0);
  return milliseconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is Map) {
    final result =
        value.entries
            .where((entry) => entry.value == true)
            .map((entry) => entry.key.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
          ..sort();
    return List<String>.unmodifiable(result);
  }
  if (value is! List ||
      value.any((item) => item is! String || item.trim().isEmpty)) {
    throw ModelValidationException(
      '$key must be a list of non-empty strings',
      json,
    );
  }
  return List<String>.unmodifiable(
    value.cast<String>().map((item) => item.trim()),
  );
}

T _enumValue<T extends Enum>(
  Map<String, dynamic> json,
  String key,
  List<T> values, {
  Map<String, T> aliases = const {},
}) {
  final raw = _requiredString(json, key);
  final alias = aliases[raw];
  if (alias != null) return alias;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw ModelValidationException('$key has an unsupported value: $raw', json);
}

List<T> _enumList<T extends Enum>(
  Map<String, dynamic> json,
  String key,
  List<T> values, {
  Map<String, T> aliases = const {},
}) {
  final raw = json[key];
  if (raw == null) return List<T>.unmodifiable(<T>[]);
  if (raw is! List) {
    throw ModelValidationException('$key must be a list', json);
  }
  final result = <T>[];
  for (final item in raw) {
    if (item is! String || item.trim().isEmpty) {
      throw ModelValidationException(
        '$key must contain non-empty strings',
        json,
      );
    }
    final normalized = item.trim();
    final value =
        aliases[normalized] ??
        values.where((candidate) => candidate.name == normalized).firstOrNull;
    if (value == null) {
      throw ModelValidationException(
        '$key has an unsupported value: $normalized',
        json,
      );
    }
    if (!result.contains(value)) result.add(value);
  }
  return List<T>.unmodifiable(result);
}

UserRole _userRole(Map<String, dynamic> json) {
  final raw = json['role'];
  if (raw is int) {
    // Legacy Firestore data used the original enum order: supervisor, worker.
    if (raw == 0) return UserRole.supervisor;
    if (raw == 1) return UserRole.worker;
  }
  return _enumValue(json, 'role', UserRole.values);
}

final class UserProfile {
  UserProfile({
    this.schemaVersion = currentSchemaVersion,
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.active,
    this.organizationName,
    List<String> siteIds = const [],
    List<String> authorizedHelmetIds = const [],
    this.pushAlertsEnabled = true,
    this.criticalAlertsOnly = false,
    this.vibrationEnabled = true,
    required DateTime updatedAt,
  }) : siteIds = List.unmodifiable(siteIds),
       authorizedHelmetIds = List.unmodifiable(authorizedHelmetIds),
       updatedAt = updatedAt.toUtc() {
    if (uid.trim().isEmpty ||
        displayName.trim().isEmpty ||
        email.trim().isEmpty) {
      throw ModelValidationException(
        'User identifiers, name, and email are required',
      );
    }
  }

  final String schemaVersion;
  final String uid;
  final String displayName;
  final String email;
  final UserRole role;
  final bool active;
  final String? organizationName;
  final List<String> siteIds;
  final List<String> authorizedHelmetIds;
  final bool pushAlertsEnabled;
  final bool criticalAlertsOnly;
  final bool vibrationEnabled;
  final DateTime updatedAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    schemaVersion: _requiredString(json, 'schemaVersion'),
    uid: _requiredString(json, 'uid'),
    displayName: _requiredString(
      json,
      json.containsKey('displayName') ? 'displayName' : 'name',
    ),
    email: _requiredString(json, 'email'),
    role: _userRole(json),
    active: json.containsKey('active') ? _requiredBool(json, 'active') : true,
    organizationName: _optionalString(
      json,
      json.containsKey('organizationName')
          ? 'organizationName'
          : 'organization',
    ),
    siteIds: _stringList(json, 'siteIds'),
    authorizedHelmetIds: _stringList(json, 'authorizedHelmetIds'),
    pushAlertsEnabled: _optionalBool(json, 'pushAlertsEnabled') ?? true,
    criticalAlertsOnly: _optionalBool(json, 'criticalAlertsOnly') ?? false,
    vibrationEnabled: _optionalBool(json, 'vibrationEnabled') ?? true,
    updatedAt: json['updatedAt'] == null
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : _requiredTimestamp(json, 'updatedAt'),
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'uid': uid,
    'displayName': displayName,
    'email': email,
    'role': role.name,
    'active': active,
    if (organizationName != null) 'organizationName': organizationName,
    'siteIds': siteIds,
    'authorizedHelmetIds': authorizedHelmetIds,
    'pushAlertsEnabled': pushAlertsEnabled,
    'criticalAlertsOnly': criticalAlertsOnly,
    'vibrationEnabled': vibrationEnabled,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  UserProfile copyWith({
    bool? pushAlertsEnabled,
    bool? criticalAlertsOnly,
    bool? vibrationEnabled,
    DateTime? updatedAt,
  }) => UserProfile(
    schemaVersion: schemaVersion,
    uid: uid,
    displayName: displayName,
    email: email,
    role: role,
    active: active,
    organizationName: organizationName,
    siteIds: siteIds,
    authorizedHelmetIds: authorizedHelmetIds,
    pushAlertsEnabled: pushAlertsEnabled ?? this.pushAlertsEnabled,
    criticalAlertsOnly: criticalAlertsOnly ?? this.criticalAlertsOnly,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

final class Site {
  Site({
    this.schemaVersion = currentSchemaVersion,
    required this.siteId,
    required this.name,
    this.organizationName,
    List<String> zones = const [],
    required this.active,
    required DateTime updatedAt,
  }) : zones = List.unmodifiable(zones),
       updatedAt = updatedAt.toUtc() {
    if (siteId.trim().isEmpty || name.trim().isEmpty) {
      throw ModelValidationException('Site ID and name are required');
    }
  }

  final String schemaVersion;
  final String siteId;
  final String name;
  final String? organizationName;
  final List<String> zones;
  final bool active;
  final DateTime updatedAt;

  factory Site.fromJson(Map<String, dynamic> json) => Site(
    schemaVersion: _requiredString(json, 'schemaVersion'),
    siteId: _requiredString(json, 'siteId'),
    name: _requiredString(json, 'name'),
    organizationName: _optionalString(json, 'organizationName'),
    zones: _stringList(json, 'zones'),
    active: _requiredBool(json, 'active'),
    updatedAt: _requiredTimestamp(json, 'updatedAt'),
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'siteId': siteId,
    'name': name,
    if (organizationName != null) 'organizationName': organizationName,
    'zones': zones,
    'active': active,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

final class Helmet {
  Helmet({
    this.schemaVersion = currentSchemaVersion,
    required this.helmetId,
    required this.siteId,
    this.assignedWorkerId,
    this.zone,
    this.firmwareVersion,
    required this.active,
    required this.provisioningStatus,
    this.connectivity,
    DateTime? lastSeenAt,
    required DateTime updatedAt,
  }) : lastSeenAt = lastSeenAt?.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (helmetId.trim().isEmpty || siteId.trim().isEmpty) {
      throw ModelValidationException('Helmet ID and site ID are required');
    }
  }

  final String schemaVersion;
  final String helmetId;
  final String siteId;
  final String? assignedWorkerId;
  final String? zone;
  final String? firmwareVersion;
  final bool active;
  final ProvisioningStatus provisioningStatus;
  final ConnectivityStatus? connectivity;
  final DateTime? lastSeenAt;
  final DateTime updatedAt;

  factory Helmet.fromJson(Map<String, dynamic> json) => Helmet(
    schemaVersion: _requiredString(json, 'schemaVersion'),
    helmetId: _requiredString(json, 'helmetId'),
    siteId: _requiredString(json, 'siteId'),
    assignedWorkerId: _optionalString(json, 'assignedWorkerId'),
    zone: _optionalString(json, 'zone'),
    firmwareVersion: _optionalString(json, 'firmwareVersion'),
    active: _requiredBool(json, 'active'),
    provisioningStatus: _enumValue(
      json,
      'provisioningStatus',
      ProvisioningStatus.values,
    ),
    connectivity: json['connectivity'] == null
        ? null
        : _enumValue(
            json,
            'connectivity',
            ConnectivityStatus.values,
            aliases: {'offline_buffering': ConnectivityStatus.offlineBuffering},
          ),
    lastSeenAt: _optionalTimestamp(json, 'lastSeenAt'),
    updatedAt: _requiredTimestamp(json, 'updatedAt'),
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'helmetId': helmetId,
    'siteId': siteId,
    if (assignedWorkerId != null) 'assignedWorkerId': assignedWorkerId,
    if (zone != null) 'zone': zone,
    if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
    'active': active,
    'provisioningStatus': provisioningStatus.name,
    if (connectivity != null)
      'connectivity': connectivity == ConnectivityStatus.offlineBuffering
          ? 'offline_buffering'
          : connectivity!.name,
    if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

final class GPSLocation {
  GPSLocation({
    required this.latitudeDegrees,
    required this.longitudeDegrees,
    this.hdop,
    required DateTime capturedAt,
    required this.isLastKnown,
  }) : capturedAt = capturedAt.toUtc() {
    _validateCoordinates(latitudeDegrees, longitudeDegrees);
    if (hdop != null && (!hdop!.isFinite || hdop! < 0 || hdop! > 5)) {
      throw ModelValidationException('HDOP must be between 0 and 5');
    }
  }

  final double latitudeDegrees;
  final double longitudeDegrees;
  final double? hdop;
  final DateTime capturedAt;
  final bool isLastKnown;

  static void _validateCoordinates(double latitude, double longitude) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ModelValidationException(
        'Latitude must be between -90 and 90 degrees',
      );
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ModelValidationException(
        'Longitude must be between -180 and 180 degrees',
      );
    }
    if (latitude == 0 && longitude == 0) {
      throw ModelValidationException(
        'The invalid 0,0 GPS sentinel is not allowed',
      );
    }
  }

  factory GPSLocation.fromJson(Map<String, dynamic> json) => GPSLocation(
    latitudeDegrees: _requiredNumber(json, 'latitude', min: -90, max: 90),
    longitudeDegrees: _requiredNumber(json, 'longitude', min: -180, max: 180),
    hdop: _optionalNumber(json, 'hdop', min: 0, max: 5),
    capturedAt: _requiredTimestamp(json, 'capturedAt'),
    isLastKnown: _requiredBool(json, 'isLastKnown'),
  );

  Map<String, dynamic> toJson() => {
    'latitude': latitudeDegrees,
    'longitude': longitudeDegrees,
    if (hdop != null) 'hdop': hdop,
    'capturedAt': capturedAt.millisecondsSinceEpoch,
    'isLastKnown': isLastKnown,
  };
}

final class SensorReading {
  SensorReading({
    this.schemaVersion = currentSchemaVersion,
    required this.eventId,
    required this.helmetId,
    required DateTime deviceTimestamp,
    required DateTime serverReceivedAt,
    this.temperatureC,
    this.humidityPct,
    this.heatIndexC,
    this.gasPpm,
    required this.gasWarmUp,
    this.gasRaw,
    this.gasAdcVoltage,
    this.gasSensorVoltage,
    this.gasDigitalThreshold,
    this.accelXG,
    this.accelYG,
    this.accelZG,
    this.gyroXDegreesPerSecond,
    this.gyroYDegreesPerSecond,
    this.gyroZDegreesPerSecond,
    this.fallStatus = FallStatus.notEvaluated,
    Iterable<SensorFault> sensorFaults = const [],
    this.location,
    required this.gpsStatus,
    this.batteryPct,
    required this.connectivity,
    required this.firmwareVersion,
    required this.severity,
  }) : sensorFaults = List<SensorFault>.unmodifiable(sensorFaults),
       deviceTimestamp = deviceTimestamp.toUtc(),
       serverReceivedAt = serverReceivedAt.toUtc() {
    if (eventId.trim().isEmpty ||
        helmetId.trim().isEmpty ||
        firmwareVersion.trim().isEmpty) {
      throw ModelValidationException(
        'Reading IDs and firmware version are required',
      );
    }
    _validateOptionalRange(temperatureC, -40, 80, 'temperatureC');
    _validateOptionalRange(humidityPct, 0, 100, 'humidityPct');
    _validateOptionalFinite(heatIndexC, 'heatIndexC');
    _validateOptionalRange(gasPpm, 10, 300, 'gasPpm');
    if (gasWarmUp && gasPpm != null) {
      throw ModelValidationException(
        'gasPpm must be unavailable while the gas sensor is warming up',
      );
    }
    if (gasRaw != null && (gasRaw! < 0 || gasRaw! > 4095)) {
      throw ModelValidationException('gasRaw is outside the 12-bit ADC range');
    }
    _validateOptionalNonNegative(gasAdcVoltage, 'gasAdcVoltage');
    _validateOptionalNonNegative(gasSensorVoltage, 'gasSensorVoltage');
    if (batteryPct != null && (batteryPct! < 0 || batteryPct! > 100)) {
      throw ModelValidationException('batteryPct is outside the allowed range');
    }
    for (final axis in [accelXG, accelYG, accelZG]) {
      if (axis != null && !axis.isFinite) {
        throw ModelValidationException('Acceleration values must be finite');
      }
    }
    for (final axis in [
      gyroXDegreesPerSecond,
      gyroYDegreesPerSecond,
      gyroZDegreesPerSecond,
    ]) {
      if (axis != null && !axis.isFinite) {
        throw ModelValidationException('Gyroscope values must be finite');
      }
    }
    if (gpsStatus == GpsStatus.valid &&
        (location == null || location!.hdop == null)) {
      throw ModelValidationException(
        'A valid GPS status requires a location with HDOP',
      );
    }
    if (location != null &&
        gpsStatus != GpsStatus.valid &&
        !location!.isLastKnown) {
      throw ModelValidationException(
        'Non-valid GPS states may only retain a last-known location',
      );
    }
    if (connectivity == ConnectivityStatus.offline) {
      throw ModelValidationException(
        'Telemetry connectivity cannot claim offline delivery',
      );
    }
  }

  static void _validateOptionalRange(
    double? value,
    double min,
    double max,
    String field,
  ) {
    if (value != null && (!value.isFinite || value < min || value > max)) {
      throw ModelValidationException('$field is outside the allowed range');
    }
  }

  static void _validateOptionalFinite(double? value, String field) {
    if (value != null && !value.isFinite) {
      throw ModelValidationException('$field must be finite');
    }
  }

  static void _validateOptionalNonNegative(double? value, String field) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw ModelValidationException('$field must be finite and non-negative');
    }
  }

  final String schemaVersion;
  final String eventId;
  final String helmetId;
  final DateTime deviceTimestamp;
  final DateTime serverReceivedAt;
  final double? temperatureC;
  final double? humidityPct;
  final double? heatIndexC;
  final double? gasPpm;
  final bool gasWarmUp;
  final int? gasRaw;
  final double? gasAdcVoltage;
  final double? gasSensorVoltage;
  final bool? gasDigitalThreshold;
  final double? accelXG;
  final double? accelYG;
  final double? accelZG;
  final double? gyroXDegreesPerSecond;
  final double? gyroYDegreesPerSecond;
  final double? gyroZDegreesPerSecond;
  final FallStatus fallStatus;
  final List<SensorFault> sensorFaults;
  final GPSLocation? location;
  final GpsStatus gpsStatus;
  final int? batteryPct;
  final ConnectivityStatus connectivity;
  final String firmwareVersion;
  final SafetySeverity severity;

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    var gpsStatus = _enumValue(json, 'gpsStatus', GpsStatus.values);
    GPSLocation? location;
    try {
      final locationJson = json['location'];
      if (locationJson != null) {
        if (locationJson is! Map) {
          throw ModelValidationException('location must be an object', json);
        }
        location = GPSLocation.fromJson(
          Map<String, dynamic>.from(locationJson),
        );
      } else if (json['latitude'] != null || json['longitude'] != null) {
        location = GPSLocation.fromJson({
          'latitude': json['latitude'],
          'longitude': json['longitude'],
          'hdop': json['hdop'],
          'capturedAt': json['gpsCapturedAt'] ?? json['deviceTimestamp'],
          'isLastKnown': json['isLastKnown'] ?? false,
        });
      }
    } on ModelValidationException {
      // A malformed GPS fix must not make otherwise valid safety telemetry
      // unusable. It is deliberately represented as an invalid, absent fix.
      location = null;
      gpsStatus = GpsStatus.invalid;
    }
    if (location == null && gpsStatus == GpsStatus.valid) {
      gpsStatus = GpsStatus.invalid;
    }
    return SensorReading(
      schemaVersion: _requiredString(json, 'schemaVersion'),
      eventId: _requiredString(json, 'eventId'),
      helmetId: _requiredString(json, 'helmetId'),
      deviceTimestamp: _requiredTimestamp(json, 'deviceTimestamp'),
      serverReceivedAt: _requiredTimestamp(json, 'serverReceivedAt'),
      temperatureC: _optionalNumber(json, 'temperatureC', min: -40, max: 80),
      humidityPct: _optionalNumber(json, 'humidityPct', min: 0, max: 100),
      heatIndexC: _optionalNumber(json, 'heatIndexC'),
      gasPpm: _optionalNumber(json, 'gasPpm', min: 10, max: 300),
      gasWarmUp: _requiredBool(json, 'gasWarmUp'),
      gasRaw: _optionalInt(json, 'gasRaw', min: 0, max: 4095),
      gasAdcVoltage: _optionalNumber(json, 'gasAdcVoltage', min: 0),
      gasSensorVoltage: _optionalNumber(json, 'gasSensorVoltage', min: 0),
      gasDigitalThreshold: _optionalBool(json, 'gasDigitalThreshold'),
      accelXG: _optionalNumber(json, 'accelXG'),
      accelYG: _optionalNumber(json, 'accelYG'),
      accelZG: _optionalNumber(json, 'accelZG'),
      gyroXDegreesPerSecond: _optionalNumber(json, 'gyroXDegreesPerSecond'),
      gyroYDegreesPerSecond: _optionalNumber(json, 'gyroYDegreesPerSecond'),
      gyroZDegreesPerSecond: _optionalNumber(json, 'gyroZDegreesPerSecond'),
      fallStatus: json['fallStatus'] == null
          ? FallStatus.notEvaluated
          : _enumValue(
              json,
              'fallStatus',
              FallStatus.values,
              aliases: const {
                'not_evaluated': FallStatus.notEvaluated,
                'free_fall_candidate': FallStatus.freeFallCandidate,
                'impact_detected': FallStatus.impactDetected,
                'stillness_candidate': FallStatus.stillnessCandidate,
              },
            ),
      sensorFaults: _enumList(
        json,
        'sensorFaults',
        SensorFault.values,
        aliases: const {
          'mpu_read_failed': SensorFault.mpuReadFailed,
          'dht_read_failed': SensorFault.dhtReadFailed,
          'mq7_read_failed': SensorFault.mq7ReadFailed,
          'mq7_uncalibrated': SensorFault.mq7Uncalibrated,
          'mq7_heater_state_unknown': SensorFault.mq7HeaterStateUnknown,
          'gps_unavailable': SensorFault.gpsUnavailable,
          'battery_unavailable': SensorFault.batteryUnavailable,
        },
      ),
      location: location,
      gpsStatus: gpsStatus,
      batteryPct: _optionalInt(json, 'batteryPct', min: 0, max: 100),
      connectivity: _enumValue(
        json,
        'connectivity',
        ConnectivityStatus.values,
        aliases: {'offline_buffering': ConnectivityStatus.offlineBuffering},
      ),
      firmwareVersion: _requiredString(json, 'firmwareVersion'),
      severity: json['severity'] == null
          ? SafetySeverity.unassessed
          : _enumValue(json, 'severity', SafetySeverity.values),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'eventId': eventId,
    'helmetId': helmetId,
    'deviceTimestamp': deviceTimestamp.millisecondsSinceEpoch,
    'serverReceivedAt': serverReceivedAt.millisecondsSinceEpoch,
    if (temperatureC != null) 'temperatureC': temperatureC,
    if (humidityPct != null) 'humidityPct': humidityPct,
    if (heatIndexC != null) 'heatIndexC': heatIndexC,
    if (gasPpm != null) 'gasPpm': gasPpm,
    'gasWarmUp': gasWarmUp,
    if (gasRaw != null) 'gasRaw': gasRaw,
    if (gasAdcVoltage != null) 'gasAdcVoltage': gasAdcVoltage,
    if (gasSensorVoltage != null) 'gasSensorVoltage': gasSensorVoltage,
    if (gasDigitalThreshold != null) 'gasDigitalThreshold': gasDigitalThreshold,
    if (accelXG != null) 'accelXG': accelXG,
    if (accelYG != null) 'accelYG': accelYG,
    if (accelZG != null) 'accelZG': accelZG,
    if (gyroXDegreesPerSecond != null)
      'gyroXDegreesPerSecond': gyroXDegreesPerSecond,
    if (gyroYDegreesPerSecond != null)
      'gyroYDegreesPerSecond': gyroYDegreesPerSecond,
    if (gyroZDegreesPerSecond != null)
      'gyroZDegreesPerSecond': gyroZDegreesPerSecond,
    'fallStatus': fallStatus.name,
    if (sensorFaults.isNotEmpty)
      'sensorFaults': sensorFaults.map((fault) => fault.name).toList(),
    if (location != null) 'location': location!.toJson(),
    'gpsStatus': gpsStatus.name,
    if (batteryPct != null) 'batteryPct': batteryPct,
    'connectivity': connectivity == ConnectivityStatus.offlineBuffering
        ? 'offline_buffering'
        : connectivity.name,
    'firmwareVersion': firmwareVersion,
    'severity': severity.name,
  };
}

final class SafetyAlert {
  SafetyAlert({
    this.schemaVersion = currentSchemaVersion,
    required this.alertId,
    required this.eventId,
    required this.helmetId,
    required this.siteId,
    this.workerId,
    required this.type,
    required this.severity,
    this.sensorValue,
    this.threshold,
    this.unit,
    Map<String, double?> evidence = const {},
    required DateTime deviceTimestamp,
    required DateTime serverReceivedAt,
    this.location,
    required this.status,
    DateTime? deliveredAt,
    this.viewedBy,
    DateTime? viewedAt,
    this.acknowledgedBy,
    DateTime? acknowledgedAt,
    this.resolvedBy,
    DateTime? resolvedAt,
    this.resolutionNote,
  }) : evidence = UnmodifiableMapView(Map<String, double?>.from(evidence)),
       deviceTimestamp = deviceTimestamp.toUtc(),
       serverReceivedAt = serverReceivedAt.toUtc(),
       deliveredAt = deliveredAt?.toUtc(),
       viewedAt = viewedAt?.toUtc(),
       acknowledgedAt = acknowledgedAt?.toUtc(),
       resolvedAt = resolvedAt?.toUtc() {
    if ([
      alertId,
      eventId,
      helmetId,
      siteId,
    ].any((value) => value.trim().isEmpty)) {
      throw ModelValidationException('Alert IDs and site ID are required');
    }
    if (sensorValue != null && !sensorValue!.isFinite ||
        threshold != null && !threshold!.isFinite ||
        evidence.values.any((value) => value != null && !value.isFinite)) {
      throw ModelValidationException('Alert evidence values must be finite');
    }
    if ((sensorValue != null || threshold != null) && unit == null) {
      throw ModelValidationException(
        'Numeric alert evidence requires an explicit unit',
      );
    }
    if (severity != SafetySeverity.warning &&
        severity != SafetySeverity.critical) {
      throw ModelValidationException(
        'Alerts must have warning or critical severity',
      );
    }
    if ((acknowledgedBy == null) != (acknowledgedAt == null)) {
      throw ModelValidationException(
        'Acknowledgement actor and time must be set together',
      );
    }
    if ((viewedBy == null) != (viewedAt == null)) {
      throw ModelValidationException(
        'Viewed actor and time must be set together',
      );
    }
    if ((resolvedBy == null) != (resolvedAt == null)) {
      throw ModelValidationException(
        'Resolution actor and time must be set together',
      );
    }
    if (evidence.isEmpty) {
      throw ModelValidationException('Every alert requires incident evidence');
    }
    if (status == AlertStatus.acknowledged && acknowledgedAt == null) {
      throw ModelValidationException(
        'Acknowledged alerts require the backend actor and timestamp',
      );
    }
    if (status == AlertStatus.resolved &&
        (acknowledgedAt == null || resolvedAt == null)) {
      throw ModelValidationException(
        'Resolved alerts require acknowledgement and resolution audit fields',
      );
    }
  }

  final String schemaVersion;
  final String alertId;
  final String eventId;
  final String helmetId;
  final String siteId;
  final String? workerId;
  final AlertType type;
  final SafetySeverity severity;
  final double? sensorValue;
  final double? threshold;
  final SensorUnit? unit;
  final Map<String, double?> evidence;
  final DateTime deviceTimestamp;
  final DateTime serverReceivedAt;
  final GPSLocation? location;
  final AlertStatus status;
  final DateTime? deliveredAt;
  final String? viewedBy;
  final DateTime? viewedAt;
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final String? resolutionNote;

  factory SafetyAlert.fromJson(Map<String, dynamic> json) {
    final rawEvidence = json['evidence'];
    final evidence = <String, double?>{};
    if (rawEvidence != null) {
      if (rawEvidence is! Map) {
        throw ModelValidationException('evidence must be an object', json);
      }
      for (final entry in rawEvidence.entries) {
        final value = entry.value;
        if (value != null && (value is! num || !value.isFinite)) {
          throw ModelValidationException(
            'evidence values must be finite numbers or null',
            json,
          );
        }
        evidence[entry.key.toString()] = (value as num?)?.toDouble();
      }
    }
    final rawLocation = json['location'];
    return SafetyAlert(
      schemaVersion: _requiredString(json, 'schemaVersion'),
      alertId: _requiredString(json, 'alertId'),
      eventId: _requiredString(json, 'eventId'),
      helmetId: _requiredString(json, 'helmetId'),
      siteId: _requiredString(json, 'siteId'),
      workerId: _optionalString(json, 'workerId'),
      type: _enumValue(
        json,
        'alertType',
        AlertType.values,
        aliases: {'sensor_fault': AlertType.sensorFault},
      ),
      severity: _enumValue(json, 'severity', SafetySeverity.values),
      sensorValue: _optionalNumber(json, 'sensorValue'),
      threshold: _optionalNumber(json, 'threshold'),
      unit: json['unit'] == null
          ? null
          : _enumValue(json, 'unit', SensorUnit.values),
      evidence: evidence,
      deviceTimestamp: _requiredTimestamp(json, 'deviceTimestamp'),
      serverReceivedAt: _requiredTimestamp(json, 'serverReceivedAt'),
      location: rawLocation == null
          ? null
          : GPSLocation.fromJson(Map<String, dynamic>.from(rawLocation as Map)),
      status: _enumValue(json, 'status', AlertStatus.values),
      deliveredAt: _optionalTimestamp(json, 'deliveredAt'),
      viewedBy: _optionalString(json, 'viewedBy'),
      viewedAt: _optionalTimestamp(json, 'viewedAt'),
      acknowledgedBy: _optionalString(json, 'acknowledgedBy'),
      acknowledgedAt: _optionalTimestamp(json, 'acknowledgedAt'),
      resolvedBy: _optionalString(json, 'resolvedBy'),
      resolvedAt: _optionalTimestamp(json, 'resolvedAt'),
      resolutionNote: _optionalString(json, 'resolutionNote'),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'alertId': alertId,
    'eventId': eventId,
    'helmetId': helmetId,
    'siteId': siteId,
    if (workerId != null) 'workerId': workerId,
    'alertType': type == AlertType.sensorFault ? 'sensor_fault' : type.name,
    'severity': severity.name,
    if (sensorValue != null) 'sensorValue': sensorValue,
    if (threshold != null) 'threshold': threshold,
    if (unit != null) 'unit': unit!.name,
    'evidence': evidence,
    'deviceTimestamp': deviceTimestamp.millisecondsSinceEpoch,
    'serverReceivedAt': serverReceivedAt.millisecondsSinceEpoch,
    if (location != null) 'location': location!.toJson(),
    'status': status.name,
    if (deliveredAt != null) 'deliveredAt': deliveredAt!.millisecondsSinceEpoch,
    if (viewedBy != null) 'viewedBy': viewedBy,
    if (viewedAt != null) 'viewedAt': viewedAt!.millisecondsSinceEpoch,
    if (acknowledgedBy != null) 'acknowledgedBy': acknowledgedBy,
    if (acknowledgedAt != null)
      'acknowledgedAt': acknowledgedAt!.millisecondsSinceEpoch,
    if (resolvedBy != null) 'resolvedBy': resolvedBy,
    if (resolvedAt != null) 'resolvedAt': resolvedAt!.millisecondsSinceEpoch,
    if (resolutionNote != null) 'resolutionNote': resolutionNote,
  };

  SafetyAlert viewed({required String actorUid, required DateTime at}) =>
      SafetyAlert(
        schemaVersion: schemaVersion,
        alertId: alertId,
        eventId: eventId,
        helmetId: helmetId,
        siteId: siteId,
        workerId: workerId,
        type: type,
        severity: severity,
        sensorValue: sensorValue,
        threshold: threshold,
        unit: unit,
        evidence: evidence,
        deviceTimestamp: deviceTimestamp,
        serverReceivedAt: serverReceivedAt,
        location: location,
        status: status == AlertStatus.created || status == AlertStatus.delivered
            ? AlertStatus.viewed
            : status,
        deliveredAt: deliveredAt,
        viewedBy: viewedBy ?? actorUid,
        viewedAt: viewedAt ?? at,
        acknowledgedBy: acknowledgedBy,
        acknowledgedAt: acknowledgedAt,
        resolvedBy: resolvedBy,
        resolvedAt: resolvedAt,
        resolutionNote: resolutionNote,
      );

  SafetyAlert acknowledged({required String actorUid, required DateTime at}) =>
      SafetyAlert(
        schemaVersion: schemaVersion,
        alertId: alertId,
        eventId: eventId,
        helmetId: helmetId,
        siteId: siteId,
        workerId: workerId,
        type: type,
        severity: severity,
        sensorValue: sensorValue,
        threshold: threshold,
        unit: unit,
        evidence: evidence,
        deviceTimestamp: deviceTimestamp,
        serverReceivedAt: serverReceivedAt,
        location: location,
        status: status == AlertStatus.resolved
            ? AlertStatus.resolved
            : AlertStatus.acknowledged,
        deliveredAt: deliveredAt,
        viewedBy: viewedBy,
        viewedAt: viewedAt,
        acknowledgedBy: acknowledgedBy ?? actorUid,
        acknowledgedAt: acknowledgedAt ?? at,
        resolvedBy: resolvedBy,
        resolvedAt: resolvedAt,
        resolutionNote: resolutionNote,
      );

  SafetyAlert resolved({
    required String actorUid,
    required DateTime at,
    required String note,
  }) => SafetyAlert(
    schemaVersion: schemaVersion,
    alertId: alertId,
    eventId: eventId,
    helmetId: helmetId,
    siteId: siteId,
    workerId: workerId,
    type: type,
    severity: severity,
    sensorValue: sensorValue,
    threshold: threshold,
    unit: unit,
    evidence: evidence,
    deviceTimestamp: deviceTimestamp,
    serverReceivedAt: serverReceivedAt,
    location: location,
    status: AlertStatus.resolved,
    deliveredAt: deliveredAt,
    viewedBy: viewedBy,
    viewedAt: viewedAt,
    acknowledgedBy: acknowledgedBy,
    acknowledgedAt: acknowledgedAt,
    resolvedBy: resolvedBy ?? actorUid,
    resolvedAt: resolvedAt ?? at,
    resolutionNote: resolutionNote ?? note,
  );
}

final class HelmetConfiguration {
  HelmetConfiguration({
    this.schemaVersion = currentSchemaVersion,
    required this.helmetId,
    required this.configVersion,
    required this.temperatureWarningC,
    required this.temperatureCriticalC,
    required this.humidityWarningLowPct,
    required this.humidityCriticalLowPct,
    required this.humidityWarningHighPct,
    required this.humidityCriticalHighPct,
    required this.gasWarningPpm,
    required this.gasCriticalPpm,
    required this.fallImpactThresholdG,
    required this.fallDuplicateCooldownSeconds,
    required this.normalPollingIntervalSeconds,
    required this.gasWarmUpHours,
    required DateTime updatedAt,
    required this.updatedBy,
  }) : updatedAt = updatedAt.toUtc() {
    final values = [
      temperatureWarningC,
      temperatureCriticalC,
      humidityWarningLowPct,
      humidityCriticalLowPct,
      humidityWarningHighPct,
      humidityCriticalHighPct,
      gasWarningPpm,
      gasCriticalPpm,
      fallImpactThresholdG,
    ];
    if (helmetId.trim().isEmpty ||
        configVersion.trim().isEmpty ||
        updatedBy.trim().isEmpty) {
      throw ModelValidationException(
        'Configuration IDs and update actor are required',
      );
    }
    if (values.any((value) => !value.isFinite)) {
      throw ModelValidationException('Configuration thresholds must be finite');
    }
    if (temperatureWarningC >= temperatureCriticalC ||
        humidityCriticalLowPct >= humidityWarningLowPct ||
        humidityWarningLowPct >= humidityWarningHighPct ||
        humidityWarningHighPct >= humidityCriticalHighPct ||
        gasWarningPpm >= gasCriticalPpm ||
        fallImpactThresholdG <= 0 ||
        fallDuplicateCooldownSeconds <= 0 ||
        normalPollingIntervalSeconds <= 0 ||
        gasWarmUpHours < 0) {
      throw ModelValidationException(
        'Configuration thresholds are not in a safe logical order',
      );
    }
  }

  final String schemaVersion;
  final String helmetId;
  final String configVersion;
  final double temperatureWarningC;
  final double temperatureCriticalC;
  final double humidityWarningLowPct;
  final double humidityCriticalLowPct;
  final double humidityWarningHighPct;
  final double humidityCriticalHighPct;
  final double gasWarningPpm;
  final double gasCriticalPpm;
  final double fallImpactThresholdG;
  final int fallDuplicateCooldownSeconds;
  final int normalPollingIntervalSeconds;
  final int gasWarmUpHours;
  final DateTime updatedAt;
  final String updatedBy;

  factory HelmetConfiguration.fromJson(
    Map<String, dynamic> json,
  ) => HelmetConfiguration(
    schemaVersion: _requiredString(json, 'schemaVersion'),
    helmetId: _requiredString(json, 'helmetId'),
    configVersion: _requiredString(json, 'configVersion'),
    temperatureWarningC: _requiredNumber(json, 'temperatureWarningC'),
    temperatureCriticalC: _requiredNumber(json, 'temperatureCriticalC'),
    humidityWarningLowPct: _requiredNumber(
      json,
      'humidityWarningLowPct',
      min: 0,
      max: 100,
    ),
    humidityCriticalLowPct: _requiredNumber(
      json,
      'humidityCriticalLowPct',
      min: 0,
      max: 100,
    ),
    humidityWarningHighPct: _requiredNumber(
      json,
      'humidityWarningHighPct',
      min: 0,
      max: 100,
    ),
    humidityCriticalHighPct: _requiredNumber(
      json,
      'humidityCriticalHighPct',
      min: 0,
      max: 100,
    ),
    gasWarningPpm: _requiredNumber(json, 'gasWarningPpm', min: 0),
    gasCriticalPpm: _requiredNumber(json, 'gasCriticalPpm', min: 0),
    fallImpactThresholdG: _requiredNumber(json, 'fallImpactThresholdG', min: 0),
    fallDuplicateCooldownSeconds:
        _optionalInt(json, 'fallDuplicateCooldownSeconds', min: 1) ??
        (throw ModelValidationException(
          'fallDuplicateCooldownSeconds is required',
          json,
        )),
    normalPollingIntervalSeconds:
        _optionalInt(json, 'normalPollingIntervalSeconds', min: 1) ??
        (throw ModelValidationException(
          'normalPollingIntervalSeconds is required',
          json,
        )),
    gasWarmUpHours:
        _optionalInt(json, 'gasWarmUpHours', min: 0) ??
        (throw ModelValidationException('gasWarmUpHours is required', json)),
    updatedAt: _requiredTimestamp(json, 'updatedAt'),
    updatedBy: _requiredString(json, 'updatedBy'),
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'helmetId': helmetId,
    'configVersion': configVersion,
    'temperatureWarningC': temperatureWarningC,
    'temperatureCriticalC': temperatureCriticalC,
    'humidityWarningLowPct': humidityWarningLowPct,
    'humidityCriticalLowPct': humidityCriticalLowPct,
    'humidityWarningHighPct': humidityWarningHighPct,
    'humidityCriticalHighPct': humidityCriticalHighPct,
    'gasWarningPpm': gasWarningPpm,
    'gasCriticalPpm': gasCriticalPpm,
    'fallImpactThresholdG': fallImpactThresholdG,
    'fallDuplicateCooldownSeconds': fallDuplicateCooldownSeconds,
    'normalPollingIntervalSeconds': normalPollingIntervalSeconds,
    'gasWarmUpHours': gasWarmUpHours,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'updatedBy': updatedBy,
  };
}

final class FallPrediction {
  const FallPrediction({
    required this.status,
    this.probability,
    this.threshold,
    this.modelVersion,
    required this.inputValid,
  });

  final InferenceStatus status;
  final double? probability;
  final double? threshold;
  final String? modelVersion;
  final bool inputValid;

  factory FallPrediction.fromJson(Map<String, dynamic> json) {
    final status = _enumValue(
      json,
      'status',
      InferenceStatus.values,
      aliases: {
        'evaluated': InferenceStatus.completed,
        'out_of_distribution': InferenceStatus.outOfDistribution,
      },
    );
    if (status == InferenceStatus.unavailable) {
      return const FallPrediction(
        status: InferenceStatus.unavailable,
        inputValid: false,
      );
    }
    if (status != InferenceStatus.completed) {
      return FallPrediction(status: status, inputValid: false);
    }
    return FallPrediction(
      status: status,
      probability: _requiredNumber(json, 'probability', min: 0, max: 1),
      threshold: _requiredNumber(json, 'threshold', min: 0, max: 1),
      modelVersion: _requiredString(json, 'modelVersion'),
      inputValid: true,
    );
  }

  Map<String, dynamic> toJson() {
    if (status != InferenceStatus.completed) {
      return const {'status': 'unavailable'};
    }
    if (probability == null || threshold == null || modelVersion == null) {
      throw ModelValidationException(
        'An evaluated fall prediction requires probability, threshold and modelVersion',
      );
    }
    return {
      'status': 'evaluated',
      'probability': probability,
      'threshold': threshold,
      'modelVersion': modelVersion,
    };
  }
}

final class GasPrediction {
  GasPrediction({
    required this.status,
    required this.gasClass,
    this.confidence,
    Map<GasClass, double> probabilities = const {},
    this.modelVersion,
    required this.inputValid,
    required this.outOfDistribution,
  }) : probabilities = Map.unmodifiable(probabilities) {
    if (confidence != null &&
        (!confidence!.isFinite || confidence! < 0 || confidence! > 1)) {
      throw ModelValidationException('Gas confidence must be between 0 and 1');
    }
    if (probabilities.values.any(
      (value) => !value.isFinite || value < 0 || value > 1,
    )) {
      throw ModelValidationException(
        'Gas probabilities must be between 0 and 1',
      );
    }
  }

  final InferenceStatus status;
  final GasClass gasClass;
  final double? confidence;
  final Map<GasClass, double> probabilities;
  final String? modelVersion;
  final bool inputValid;
  final bool outOfDistribution;

  static GasClass _parseClass(Object? raw) {
    if (raw == null) return GasClass.unknown;
    if (raw is! String) {
      throw ModelValidationException('gasClass must be a string');
    }
    return switch (raw.trim().toLowerCase().replaceAll('_', '')) {
      'mixture' => GasClass.mixture,
      'nogas' => GasClass.noGas,
      'perfume' => GasClass.perfume,
      'smoke' => GasClass.smoke,
      'unknown' => GasClass.unknown,
      _ => throw ModelValidationException(
        'gasClass has an unsupported value: $raw',
      ),
    };
  }

  factory GasPrediction.fromJson(Map<String, dynamic> json) {
    final status = _enumValue(
      json,
      'status',
      InferenceStatus.values,
      aliases: {
        'evaluated': InferenceStatus.completed,
        'out_of_distribution': InferenceStatus.outOfDistribution,
      },
    );
    if (status == InferenceStatus.unavailable) {
      return GasPrediction(
        status: status,
        gasClass: GasClass.unknown,
        inputValid: false,
        outOfDistribution: false,
      );
    }
    final rawProbabilities = json['probabilities'];
    final probabilities = <GasClass, double>{};
    if (rawProbabilities is! Map) {
      throw ModelValidationException('probabilities must be an object', json);
    }
    for (final entry in rawProbabilities.entries) {
      final value = entry.value;
      if (value is! num || !value.isFinite) {
        throw ModelValidationException(
          'probabilities must contain finite numbers',
          json,
        );
      }
      probabilities[_parseClass(entry.key.toString())] = value.toDouble();
    }
    const expectedClasses = {
      GasClass.mixture,
      GasClass.noGas,
      GasClass.perfume,
      GasClass.smoke,
    };
    if (probabilities.keys.toSet().difference(expectedClasses).isNotEmpty ||
        expectedClasses.difference(probabilities.keys.toSet()).isNotEmpty) {
      throw ModelValidationException(
        'An evaluated gas prediction requires all four class probabilities',
        json,
      );
    }
    final total = probabilities.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    if ((total - 1).abs() > 0.001) {
      throw ModelValidationException('Gas probabilities must sum to one', json);
    }
    final classValue =
        json['classification'] ??
        json['gasClass'] ??
        json['predictedClass'] ??
        json['class'];
    final gasClass = _parseClass(classValue);
    final confidence = _requiredNumber(json, 'confidence', min: 0, max: 1);
    final modelVersion = _requiredString(json, 'modelVersion');
    if (gasClass == GasClass.unknown ||
        (probabilities[gasClass]! - confidence).abs() > 0.000001 ||
        probabilities.values.any((value) => value > confidence)) {
      throw ModelValidationException(
        'Gas classification and confidence must match the highest probability',
        json,
      );
    }
    return GasPrediction(
      status: status,
      gasClass: gasClass,
      confidence: confidence,
      probabilities: probabilities,
      modelVersion: modelVersion,
      inputValid: status == InferenceStatus.completed,
      outOfDistribution:
          _optionalBool(json, 'outOfDistribution') ??
          json['status'] == 'out_of_distribution' ||
              json['status'] == 'outOfDistribution',
    );
  }

  Map<String, dynamic> toJson() {
    if (status != InferenceStatus.completed) {
      return const {'status': 'unavailable'};
    }
    if (gasClass == GasClass.unknown ||
        confidence == null ||
        modelVersion == null) {
      throw ModelValidationException(
        'An evaluated gas prediction requires class, confidence and modelVersion',
      );
    }
    String className(GasClass value) => switch (value) {
      GasClass.mixture => 'Mixture',
      GasClass.noGas => 'NoGas',
      GasClass.perfume => 'Perfume',
      GasClass.smoke => 'Smoke',
      GasClass.unknown => throw ModelValidationException(
        'Unknown is not a canonical gas class',
      ),
    };
    return {
      'status': 'evaluated',
      'classification': className(gasClass),
      'confidence': confidence,
      'probabilities': {
        for (final entry in probabilities.entries)
          if (entry.key != GasClass.unknown) className(entry.key): entry.value,
      },
      'modelVersion': modelVersion,
      'outOfDistribution': outOfDistribution,
    };
  }
}

final class SafetyAssessment {
  SafetyAssessment({
    required this.schemaVersion,
    required this.assessmentId,
    required this.helmetId,
    required this.sourceEventId,
    required this.sourceSchemaVersion,
    required DateTime deviceTimestamp,
    required DateTime sourceServerReceivedAt,
    required DateTime assessedAt,
    required this.status,
    required this.overallRisk,
    required this.fall,
    required this.gas,
    required this.environmentStatus,
    required this.temperatureRisk,
    required this.humidityRisk,
    required this.heatIndexRisk,
    List<String> reasonCodes = const [],
    List<String> recommendationCodes = const [],
    this.modelBundleVersion,
  }) : deviceTimestamp = deviceTimestamp.toUtc(),
       sourceServerReceivedAt = sourceServerReceivedAt.toUtc(),
       assessedAt = assessedAt.toUtc(),
       reasonCodes = List.unmodifiable(reasonCodes),
       recommendationCodes = List.unmodifiable(recommendationCodes) {
    if (schemaVersion.trim().isEmpty ||
        assessmentId.trim().isEmpty ||
        helmetId.trim().isEmpty ||
        sourceEventId.trim().isEmpty) {
      throw ModelValidationException('Assessment identifiers are required');
    }
    if (assessmentId != sourceEventId) {
      throw ModelValidationException(
        'assessmentId must equal the source eventId',
      );
    }
  }

  static const Map<String, String> approvedRecommendations = {
    'CHECK_WORKER_IMMEDIATELY':
        'Check the worker immediately and confirm they are responsive.',
    'FOLLOW_SITE_EMERGENCY_PROTOCOL':
        'Follow the approved site emergency protocol.',
    'MOVE_TO_FRESH_AIR': 'Move to fresh air when it is safe to do so.',
    'INVESTIGATE_GAS_SOURCE':
        'Have authorized personnel investigate the possible gas source.',
    'VENTILATE_AREA_IF_SAFE':
        'Ventilate the area only when site procedures allow it.',
    'MONITOR_ENVIRONMENT': 'Continue monitoring the environment.',
    'VERIFY_SENSORS':
        'Inspect the helmet sensors before relying on this assessment.',
    'ALLOW_GAS_SENSOR_WARMUP':
        'Allow the gas sensors to warm up before using their result.',
    'HYDRATE_AND_COOL_DOWN':
        'Hydrate and move to a cooler area according to site procedures.',
    'MOVE_TO_SAFE_TEMPERATURE':
        'Move away from the temperature hazard to a designated safe area.',
    'NO_IMMEDIATE_ACTION':
        'No immediate action is indicated; continue normal monitoring.',
  };

  final String schemaVersion;
  final String assessmentId;
  final String helmetId;
  final String sourceEventId;
  final String sourceSchemaVersion;
  final DateTime deviceTimestamp;
  final DateTime sourceServerReceivedAt;
  final DateTime assessedAt;
  final InferenceStatus status;
  final AssessmentRisk overallRisk;
  final FallPrediction fall;
  final GasPrediction gas;
  final InferenceStatus environmentStatus;
  final ComponentRisk temperatureRisk;
  final ComponentRisk humidityRisk;
  final ComponentRisk heatIndexRisk;
  final List<String> reasonCodes;
  final List<String> recommendationCodes;
  final String? modelBundleVersion;

  List<String> get recommendations => List.unmodifiable(
    recommendationCodes
        .map((code) => approvedRecommendations[code])
        .whereType<String>(),
  );

  bool get hasUsableInference =>
      status == InferenceStatus.completed &&
      fall.status == InferenceStatus.completed &&
      fall.inputValid &&
      gas.status == InferenceStatus.completed &&
      gas.inputValid &&
      !gas.outOfDistribution &&
      environmentStatus == InferenceStatus.completed;

  AssessmentRisk get displayRisk =>
      overallRisk == AssessmentRisk.safe && !hasUsableInference
      ? AssessmentRisk.unknown
      : overallRisk;

  bool matchesReading(SensorReading reading) =>
      helmetId == reading.helmetId &&
      sourceEventId == reading.eventId &&
      !assessedAt.isBefore(
        reading.serverReceivedAt.subtract(const Duration(seconds: 5)),
      );

  factory SafetyAssessment.fromJson(Map<String, dynamic> json) {
    final fall = json['fall'];
    final gas = json['gas'];
    if (fall is! Map || gas is! Map) {
      throw ModelValidationException(
        'Assessment fall and gas predictions are required',
        json,
      );
    }
    final fallPrediction = FallPrediction.fromJson({
      for (final entry in fall.entries) entry.key.toString(): entry.value,
    });
    final gasPrediction = GasPrediction.fromJson({
      for (final entry in gas.entries) entry.key.toString(): entry.value,
    });
    final environment = json['environment'];
    final environmentJson = environment is Map
        ? {
            for (final entry in environment.entries)
              entry.key.toString(): entry.value,
          }
        : const <String, dynamic>{'status': 'unavailable'};
    final environmentStatus = _enumValue(
      environmentJson,
      'status',
      InferenceStatus.values,
      aliases: {
        'evaluated': InferenceStatus.completed,
        'out_of_distribution': InferenceStatus.outOfDistribution,
      },
    );
    final inferredStatus =
        <InferenceStatus>[
          fallPrediction.status,
          gasPrediction.status,
          environmentStatus,
        ].contains(InferenceStatus.error)
        ? InferenceStatus.error
        : <InferenceStatus>[
            fallPrediction.status,
            gasPrediction.status,
            environmentStatus,
          ].contains(InferenceStatus.pending)
        ? InferenceStatus.pending
        : <InferenceStatus>[
            fallPrediction.status,
            gasPrediction.status,
            environmentStatus,
          ].contains(InferenceStatus.outOfDistribution)
        ? InferenceStatus.outOfDistribution
        : fallPrediction.status == InferenceStatus.completed &&
              gasPrediction.status == InferenceStatus.completed
        ? InferenceStatus.completed
        : InferenceStatus.unavailable;
    return SafetyAssessment(
      schemaVersion: _requiredString(json, 'schemaVersion'),
      assessmentId: _requiredString(json, 'assessmentId'),
      helmetId: _requiredString(json, 'helmetId'),
      sourceEventId: _requiredString(
        json,
        json.containsKey('sourceEventId') ? 'sourceEventId' : 'eventId',
      ),
      sourceSchemaVersion: _requiredString(json, 'sourceSchemaVersion'),
      deviceTimestamp: _requiredTimestamp(json, 'deviceTimestamp'),
      sourceServerReceivedAt: _requiredTimestamp(
        json,
        'sourceServerReceivedAt',
      ),
      assessedAt: _requiredTimestamp(json, 'assessedAt'),
      status: json['status'] == null
          ? inferredStatus
          : _enumValue(
              json,
              'status',
              InferenceStatus.values,
              aliases: {
                'out_of_distribution': InferenceStatus.outOfDistribution,
              },
            ),
      overallRisk: _enumValue(
        json,
        'overallRisk',
        AssessmentRisk.values,
        aliases: {'unassessed': AssessmentRisk.unknown},
      ),
      fall: fallPrediction,
      gas: gasPrediction,
      environmentStatus: environmentStatus,
      temperatureRisk: _enumValue(
        environmentJson,
        'temperatureRisk',
        ComponentRisk.values,
      ),
      humidityRisk: _enumValue(
        environmentJson,
        'humidityRisk',
        ComponentRisk.values,
      ),
      heatIndexRisk: _enumValue(
        environmentJson,
        'heatIndexRisk',
        ComponentRisk.values,
      ),
      reasonCodes: _stringList(json, 'reasonCodes'),
      recommendationCodes: _stringList(json, 'recommendationCodes'),
      modelBundleVersion: _optionalString(json, 'modelBundleVersion'),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'assessmentId': assessmentId,
    'helmetId': helmetId,
    'eventId': sourceEventId,
    'sourceSchemaVersion': sourceSchemaVersion,
    'deviceTimestamp': deviceTimestamp.millisecondsSinceEpoch,
    'sourceServerReceivedAt': sourceServerReceivedAt.millisecondsSinceEpoch,
    'assessedAt': assessedAt.millisecondsSinceEpoch,
    'overallRisk': overallRisk.name,
    'fall': fall.toJson(),
    'gas': gas.toJson(),
    'environment': {
      'status': environmentStatus == InferenceStatus.completed
          ? 'evaluated'
          : 'unavailable',
      'temperatureRisk': temperatureRisk.name,
      'humidityRisk': humidityRisk.name,
      'heatIndexRisk': heatIndexRisk.name,
    },
    'reasonCodes': reasonCodes,
    'recommendationCodes': recommendationCodes,
    if (modelBundleVersion != null) 'modelBundleVersion': modelBundleVersion,
  };
}
