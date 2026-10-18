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

String alertTypeLabel(AlertType type) => switch (type) {
  AlertType.gas => 'Gas Level',
  AlertType.temperature => 'High Temperature',
  AlertType.humidity => 'High Humidity',
  AlertType.fall => 'Fall Detected',
  AlertType.battery => 'Low Battery',
  AlertType.sensorFault => 'Sensor Fault',
  AlertType.connectivity => 'Connectivity',
};
