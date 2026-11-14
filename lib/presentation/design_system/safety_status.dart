import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// The seven safety states the interface can communicate.
///
/// Each state has a distinct colour, a distinct icon and a text label, so a
/// hazard is never communicated by colour alone (WCAG 1.4.1). Only [normal]
/// ever means "safe"; anything uncertain maps to [unknown] or [pending].
enum SafetyStatus {
  /// Validated readings within safe limits (FR-MD-03 green).
  normal,

  /// Threshold approached; attention needed (FR-MD-03 yellow).
  warning,

  /// Threshold exceeded or sensor fault; act now (FR-MD-03 red).
  critical,

  /// No data from the helmet within the freshness window (FR-MD-04).
  offline,

  /// Showing last-known values that are no longer live.
  stale,

  /// Result not available yet (loading, sensor warm-up, assessment running).
  pending,

  /// Safety cannot be determined (no data, access or backend problem).
  unknown,
}

/// Colour roles for one [SafetyStatus].
///
/// * [tint] + [line] + [text]: chips and banners on light surfaces (text AAA).
/// * [strong]: icons, rails, gauges and dots on light surfaces (≥ 3:1).
/// * [onInk]: text and indicators on the dark chrome (AAA).
@immutable
final class StatusPalette {
  const StatusPalette({
    required this.strong,
    required this.text,
    required this.tint,
    required this.line,
    required this.onInk,
  });

  final Color strong;
  final Color text;
  final Color tint;
  final Color line;
  final Color onInk;
}

extension SafetyStatusStyle on SafetyStatus {
  StatusPalette get palette => switch (this) {
    SafetyStatus.normal => const StatusPalette(
      strong: Color(0xFF039855),
      text: Color(0xFF05603A),
      tint: Color(0xFFECFDF3),
      line: Color(0xFFABEFC6),
      onInk: Color(0xFF47CD89),
    ),
    SafetyStatus.warning => const StatusPalette(
      strong: Color(0xFFA16207),
      text: Color(0xFF713F12),
      tint: Color(0xFFFEFCE8),
      line: Color(0xFFFDE68A),
      onInk: Color(0xFFFDE047),
    ),
    SafetyStatus.critical => const StatusPalette(
      strong: Color(0xFFD92D20),
      text: Color(0xFF912018),
      tint: Color(0xFFFEF3F2),
      line: Color(0xFFFECDCA),
      onInk: Color(0xFFFF8F87),
    ),
    SafetyStatus.offline => const StatusPalette(
      strong: Color(0xFF475467),
      text: Color(0xFF1D2939),
      tint: Color(0xFFF2F4F7),
      line: Color(0xFFD0D5DD),
      onInk: Color(0xFFD0D5DD),
    ),
    SafetyStatus.stale => const StatusPalette(
      strong: Color(0xFF0E7490),
      text: Color(0xFF164E63),
      tint: Color(0xFFECFEFF),
      line: Color(0xFFA5F3FC),
      onInk: Color(0xFF67E8F9),
    ),
    SafetyStatus.pending => const StatusPalette(
      strong: Color(0xFF2563EB),
      text: Color(0xFF1E3A8A),
      tint: Color(0xFFEFF6FF),
      line: Color(0xFFBFDBFE),
      onInk: Color(0xFF93C5FD),
    ),
    SafetyStatus.unknown => const StatusPalette(
      strong: Color(0xFF667085),
      text: Color(0xFF344054),
      tint: Color(0xFFF9FAFB),
      line: Color(0xFFD0D5DD),
      onInk: Color(0xFFB4BFCF),
    ),
  };

  IconData get icon => switch (this) {
    SafetyStatus.normal => Icons.check_circle_rounded,
    SafetyStatus.warning => Icons.warning_amber_rounded,
    SafetyStatus.critical => Icons.error_rounded,
    SafetyStatus.offline => Icons.wifi_off_rounded,
    SafetyStatus.stale => Icons.history_rounded,
    SafetyStatus.pending => Icons.hourglass_top_rounded,
    SafetyStatus.unknown => Icons.help_outline_rounded,
  };

  /// Default human-readable label. Screens may pass a more specific one.
  String get label => switch (this) {
    SafetyStatus.normal => 'Normal',
    SafetyStatus.warning => 'Warning',
    SafetyStatus.critical => 'Critical',
    SafetyStatus.offline => 'Connection lost',
    SafetyStatus.stale => 'Stale',
    SafetyStatus.pending => 'Pending',
    SafetyStatus.unknown => 'Unknown',
  };

  /// Whether this status asks for the user's attention.
  bool get needsAttention =>
      this == SafetyStatus.warning || this == SafetyStatus.critical;
}

/// Maps the dashboard's [MonitoringState] onto a [SafetyStatus].
///
/// Only [MonitoringState.safe] becomes [SafetyStatus.normal]. Access and
/// backend problems become [SafetyStatus.unknown] because safety cannot be
/// determined — they are never shown as safe.
SafetyStatus safetyStatusForMonitoringState(MonitoringState state) =>
    switch (state) {
      MonitoringState.safe => SafetyStatus.normal,
      MonitoringState.warning => SafetyStatus.warning,
      MonitoringState.critical ||
      MonitoringState.sensorFault => SafetyStatus.critical,
      MonitoringState.offline => SafetyStatus.offline,
      MonitoringState.stale => SafetyStatus.stale,
      MonitoringState.loading ||
      MonitoringState.warmingUp => SafetyStatus.pending,
      MonitoringState.empty ||
      MonitoringState.permissionDenied ||
      MonitoringState.backendError => SafetyStatus.unknown,
    };

/// Maps an alert or reading [SafetySeverity] onto a [SafetyStatus].
SafetyStatus safetyStatusForSeverity(SafetySeverity severity) =>
    switch (severity) {
      SafetySeverity.safe => SafetyStatus.normal,
      SafetySeverity.warning => SafetyStatus.warning,
      SafetySeverity.critical => SafetyStatus.critical,
      SafetySeverity.unassessed => SafetyStatus.unknown,
    };

/// Maps an AI [AssessmentRisk] onto a [SafetyStatus].
SafetyStatus safetyStatusForAssessmentRisk(AssessmentRisk risk) =>
    switch (risk) {
      AssessmentRisk.safe => SafetyStatus.normal,
      AssessmentRisk.warning => SafetyStatus.warning,
      AssessmentRisk.critical => SafetyStatus.critical,
      AssessmentRisk.unknown => SafetyStatus.unknown,
    };
