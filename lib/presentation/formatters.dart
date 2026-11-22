import '../domain/models.dart';

String formatNumber(num? value, {int fractionDigits = 1}) {
  if (value == null) return 'Unavailable';
  final rounded = value.toStringAsFixed(fractionDigits);
  return rounded.endsWith('.0')
      ? rounded.substring(0, rounded.length - 2)
      : rounded;
}

String formatMeasurement(
  num? value,
  SensorUnit unit, {
  int fractionDigits = 1,
}) => value == null
    ? 'Unavailable'
    : '${formatNumber(value, fractionDigits: fractionDigits)} ${unit.symbol}';

String formatRelativeTime(DateTime timestamp, {DateTime? nowUtc}) {
  final difference = (nowUtc ?? DateTime.now().toUtc()).difference(
    timestamp.toUtc(),
  );
  if (difference.isNegative || difference.inSeconds < 60) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays == 1) return 'Yesterday';
  return '${difference.inDays} days ago';
}

String formatCoordinates(GPSLocation? location) {
  if (location == null) return 'Location unavailable';
  final latitudeDirection = location.latitudeDegrees >= 0 ? 'N' : 'S';
  final longitudeDirection = location.longitudeDegrees >= 0 ? 'E' : 'W';
  return '${location.latitudeDegrees.abs().toStringAsFixed(4)}° $latitudeDirection, '
      '${location.longitudeDegrees.abs().toStringAsFixed(4)}° $longitudeDirection';
}

String formatWorkerLocationStatus(
  WorkerLocation? location, {
  DateTime? now,
}) {
  if (location == null) return 'Location off';
  final age = (now ?? DateTime.now()).toUtc().difference(location.updatedAt);
  if (age > const Duration(minutes: 2)) return 'Location may be stale';
  final seconds = age.isNegative ? 0 : age.inSeconds;
  return 'Sharing location · updated ${seconds}s ago';
}

String formatAlertDeliveryStatus(SafetyAlert alert) {
  if (alert.deliveredAt != null) return 'Delivered';
  final delivery = alert.notificationDelivery;
  if (delivery?.inProgress == true) return 'Pending';
  if (delivery?.noAuthorizedTokens == true) {
    return 'No supervisor device registered';
  }
  if (delivery?.failed == true) return 'Delivery failed';
  return 'Not attempted';
}

String alertTypeLabel(AlertType type) => switch (type) {
  AlertType.gas => 'Gas Level',
  AlertType.temperature => 'High Temperature',
  AlertType.humidity => 'High Humidity',
  AlertType.fall => 'Fall Detected',
  AlertType.battery => 'Low Battery',
  AlertType.sensorFault => 'Sensor Fault',
  AlertType.connectivity => 'Connectivity',
};

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Unambiguous, readable UTC timestamp: `2026-11-08 14:32:05 UTC`.
String formatUtcTimestamp(DateTime timestamp) {
  final utc = timestamp.toUtc();
  return '${utc.year}-${_twoDigits(utc.month)}-${_twoDigits(utc.day)} '
      '${_twoDigits(utc.hour)}:${_twoDigits(utc.minute)}:'
      '${_twoDigits(utc.second)} UTC';
}
