import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../../domain/models.dart';
import '../design_system/design_system.dart';
import '../formatters.dart';
import '../monitoring_state.dart';
import 'admin_shared.dart';

/// A reading older than this is shown as stale (same window as the
/// supervisor dashboard's `staleAfter`).
const Duration adminLiveStaleAfter = Duration(seconds: 30);

/// A reading older than this is shown as offline.
const Duration adminLiveOfflineAfter = Duration(minutes: 5);

/// Live status of one helmet card: a [SafetyStatus] plus its text label
/// (status is never conveyed by colour alone).
typedef AdminLiveState = ({SafetyStatus status, String label, int rank});

const _readFailures = {
  SensorFault.mpuReadFailed,
  SensorFault.dhtReadFailed,
  SensorFault.mq7ReadFailed,
};

/// Derives the card state for [helmet] at [now]. Pure, so it is unit
/// tested without widgets. A missing, unreadable or old reading is never
/// shown as safe; an AI assessment may only elevate the state, and only
/// when it belongs to the reading on screen.
AdminLiveState adminLiveStateFor(
  AdminLiveHelmet helmet, {
  required DateTime now,
  bool? connected,
}) {
  AdminLiveState state(SafetyStatus status, String label, int rank) =>
      (status: status, label: label, rank: rank);

  if (helmet.meta.isRevoked) return state(SafetyStatus.unknown, 'Retired', 8);
  if (helmet.telemetryUnreadable) {
    return state(SafetyStatus.unknown, 'Unreadable data', 3);
  }
  final reading = helmet.current;
  if (reading == null) return state(SafetyStatus.unknown, 'No data yet', 7);
  if (connected == false) {
    return state(SafetyStatus.stale, 'Connection lost', 4);
  }
  final age = now.toUtc().difference(reading.serverReceivedAt);
  if (age > adminLiveOfflineAfter) {
    return state(SafetyStatus.offline, 'Offline', 6);
  }
  if (age > adminLiveStaleAfter) return state(SafetyStatus.stale, 'Stale', 5);

  final assessment = helmet.assessment;
  final risk = assessment != null && assessment.matchesReading(reading)
      ? assessment.displayRisk
      : AssessmentRisk.unknown;
  if (reading.fallStatus == FallStatus.confirmed) {
    return state(SafetyStatus.critical, 'Fall detected', 0);
  }
  if (risk == AssessmentRisk.critical ||
      reading.severity == SafetySeverity.critical) {
    return state(SafetyStatus.critical, 'Critical', 0);
  }
  if (reading.sensorFaults.any(_readFailures.contains)) {
    return state(SafetyStatus.critical, 'Sensor fault', 1);
  }
  if (risk == AssessmentRisk.warning ||
      reading.severity == SafetySeverity.warning) {
    return state(SafetyStatus.warning, 'Warning', 2);
  }
  if (reading.gasWarmUp) return state(SafetyStatus.pending, 'Warming up', 2);
  if (reading.severity == SafetySeverity.unassessed) {
    return state(SafetyStatus.unknown, 'Unassessed', 3);
  }
  return state(SafetyStatus.normal, 'Safe', 9);
}

/// "12s ago" / "4m ago" — second precision, unlike [formatRelativeTime],
/// because this screen exists to show that data is arriving right now.
String formatLiveAge(DateTime timestamp, DateTime now) {
  final age = now.toUtc().difference(timestamp.toUtc());
  if (age.isNegative || age.inSeconds < 1) return 'now';
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  if (age.inMinutes < 60) return '${age.inMinutes}m ago';
  return formatRelativeTime(timestamp, nowUtc: now);
}

/// Real-time fleet monitor for administrators: every helmet's latest
/// reading and assessment plus the newest alerts, streamed from the live
/// database (`/helmets`, `/alerts`, `.info/connected`).
class AdminLiveScreen extends StatefulWidget {
  const AdminLiveScreen({
    super.key,
    required this.admin,
    required this.onSignOut,
    this.clock,
    this.tick = const Duration(seconds: 1),
  });

  final AdminRepository admin;
  final VoidCallback onSignOut;

  /// Injectable for tests; defaults to the wall clock.
  final DateTime Function()? clock;

  /// How often ages ("12s ago") and stale states are re-evaluated.
  final Duration tick;

  @override
  State<AdminLiveScreen> createState() => _AdminLiveScreenState();
}

class _AdminLiveScreenState extends State<AdminLiveScreen> {
  late Stream<List<AdminLiveHelmet>> _fleet;
  late Stream<List<SafetyAlert>> _alerts;
  StreamSubscription<bool>? _connectionSubscription;
  Timer? _ticker;
  bool? _connected;

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    _subscribe();
    _ticker = Timer.periodic(widget.tick, (_) {
      if (mounted) setState(() {});
    });
  }

  void _subscribe() {
    _fleet = widget.admin.watchLiveFleet();
    _alerts = widget.admin.watchRecentAlerts(limit: 20);
    _connectionSubscription?.cancel();
    _connectionSubscription = widget.admin.watchBackendConnection().listen(
      (connected) {
        if (mounted) setState(() => _connected = connected);
      },
      onError: (Object _) {
        if (mounted) setState(() => _connected = false);
      },
    );
  }

  void _retry() => setState(_subscribe);

  @override
  void dispose() {
    _ticker?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminPageFrame(
    title: 'Live monitor',
    eyebrow: 'Administrator',
    subtitle: 'Real-time helmet telemetry and alerts',
    actions: [
      HeaderIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Sign out',
        onPressed: widget.onSignOut,
      ),
    ],
    headerBottom: Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConnectionIndicator(
        sourceLabel: 'Live database',
        connected: _connected,
      ),
    ),
    child: StreamBuilder<List<AdminLiveHelmet>>(
      stream: _fleet,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StateView(
            kind: StateViewKind.error,
            title: 'Live data unavailable',
            message: adminErrorMessage(snapshot.error!),
            onAction: _retry,
          );
        }
        final fleet = snapshot.data;
        if (fleet == null) {
          return const StateView(
            kind: StateViewKind.loading,
            title: 'Connecting',
            message: 'Subscribing to live helmet telemetry…',
          );
        }
        final now = _now();
        final rows = [
          for (final helmet in fleet)
            (
              helmet: helmet,
              state: adminLiveStateFor(
                helmet,
                now: now,
                connected: _connected,
              ),
            ),
        ]..sort((a, b) {
            final byRank = a.state.rank.compareTo(b.state.rank);
            return byRank != 0
                ? byRank
                : a.helmet.helmetId.compareTo(b.helmet.helmetId);
          });
        int count(bool Function(AdminLiveState) test) =>
            rows.where((row) => test(row.state)).length;
        final live = count(
          (s) =>
              s.status != SafetyStatus.stale &&
              s.status != SafetyStatus.offline &&
              s.label != 'No data yet' &&
              s.label != 'Retired' &&
              s.label != 'Unreadable data',
        );
        final critical = count((s) => s.status == SafetyStatus.critical);
        final warning = count((s) => s.status == SafetyStatus.warning);
        final silent = count(
          (s) =>
              s.status == SafetyStatus.stale ||
              s.status == SafetyStatus.offline,
        );

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            ResponsiveTileGrid(
              children: [
                MetricTile(
                  label: 'Reporting now',
                  value: '$live/${fleet.length}',
                  icon: Icons.sensors_rounded,
                  status: SafetyStatus.normal,
                ),
                MetricTile(
                  label: 'Critical',
                  value: '$critical',
                  icon: Icons.error_rounded,
                  status: critical > 0
                      ? SafetyStatus.critical
                      : SafetyStatus.normal,
                ),
                MetricTile(
                  label: 'Warning',
                  value: '$warning',
                  icon: Icons.warning_amber_rounded,
                  status: warning > 0
                      ? SafetyStatus.warning
                      : SafetyStatus.normal,
                ),
                MetricTile(
                  label: 'Stale / offline',
                  value: '$silent',
                  icon: Icons.cloud_off_outlined,
                  status: silent > 0 ? SafetyStatus.stale : SafetyStatus.normal,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Helmets',
              subtitle: 'Latest reading per helmet, updating live',
            ),
            const SizedBox(height: AppSpacing.md),
            if (rows.isEmpty)
              const StateView(
                kind: StateViewKind.empty,
                title: 'No helmets in the database',
                message:
                    'Helmets appear here as soon as they are registered '
                    'or send their first reading.',
              )
            else
              for (final row in rows) ...[
                AdminLiveHelmetCard(
                  helmet: row.helmet,
                  state: row.state,
                  now: now,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Latest alerts',
              subtitle: 'Newest 20 across the whole fleet',
            ),
            const SizedBox(height: AppSpacing.md),
            _AlertFeed(stream: _alerts, now: now),
          ],
        );
      },
    ),
  );
}

class AdminLiveHelmetCard extends StatelessWidget {
  const AdminLiveHelmetCard({
    super.key,
    required this.helmet,
    required this.state,
    required this.now,
  });

  final AdminLiveHelmet helmet;
  final AdminLiveState state;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final reading = helmet.current;
    final meta = helmet.meta;
    final details = [
      meta.assignedWorkerId == null
          ? 'Unassigned'
          : 'Worker ${meta.assignedWorkerId}',
      if (meta.siteId != null) 'Site ${meta.siteId}',
      if (reading != null)
        'updated ${formatLiveAge(reading.serverReceivedAt, now)}',
    ].join(' • ');
    return AppCard(
      status: state.status,
      semanticLabel: '${meta.label ?? meta.helmetId}, ${state.label}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: Icons.engineering_rounded, status: state.status),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta.label ?? meta.helmetId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyStrong.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    StatusChip(status: state.status, label: state.label),
                  ],
                ),
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (reading != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _Value(
                        icon: Icons.thermostat_rounded,
                        text: formatMeasurement(
                          reading.temperatureC,
                          SensorUnit.degreesCelsius,
                        ),
                      ),
                      _Value(
                        icon: Icons.water_drop_outlined,
                        text: formatMeasurement(
                          reading.humidityPct,
                          SensorUnit.percentRelativeHumidity,
                        ),
                      ),
                      _Value(
                        icon: Icons.air_rounded,
                        text: reading.gasWarmUp
                            ? 'CO warming up'
                            : 'CO ${formatMeasurement(reading.gasPpm, SensorUnit.partsPerMillion)}',
                      ),
                      _Value(
                        icon: Icons.personal_injury_outlined,
                        text: _fallLabel(reading.fallStatus),
                      ),
                      if (reading.batteryPct != null)
                        _Value(
                          icon: Icons.battery_std_rounded,
                          text: '${reading.batteryPct}%',
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _fallLabel(FallStatus status) => switch (status) {
  FallStatus.confirmed => 'Fall confirmed',
  FallStatus.impactDetected ||
  FallStatus.freeFallCandidate ||
  FallStatus.stillnessCandidate => 'Possible fall',
  FallStatus.cooldown => 'Fall cooldown',
  FallStatus.normal => 'No fall',
  FallStatus.notEvaluated => 'Fall not evaluated',
};

class _Value extends StatelessWidget {
  const _Value({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: AppSizes.iconSm, color: AppColors.textSecondary),
      const SizedBox(width: AppSpacing.xs),
      Text(
        text,
        style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
      ),
    ],
  );
}

class _AlertFeed extends StatelessWidget {
  const _AlertFeed({required this.stream, required this.now});

  final Stream<List<SafetyAlert>> stream;
  final DateTime now;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SafetyAlert>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return StateView(
          kind: StateViewKind.error,
          title: 'Alerts unavailable',
          message: adminErrorMessage(snapshot.error!),
        );
      }
      final alerts = snapshot.data;
      if (alerts == null) {
        return const StateView(
          kind: StateViewKind.loading,
          title: 'Loading alerts',
          message: 'Reading the newest alerts…',
        );
      }
      if (alerts.isEmpty) {
        return const StateView(
          kind: StateViewKind.empty,
          title: 'No alerts stored',
          message: 'New alerts appear here the moment they are raised.',
        );
      }
      return Column(
        children: [
          for (final alert in alerts) ...[
            AppCard(
              status: safetyStatusForSeverity(alert.severity),
              child: Row(
                children: [
                  IconTile(
                    icon: alertTypeIcon(alert.type),
                    status: safetyStatusForSeverity(alert.severity),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alertTypeLabel(alert.type),
                          style: AppTypography.bodyStrong.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${alert.helmetId} • ${alert.status.name} • '
                          '${formatLiveAge(alert.serverReceivedAt, now)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    },
  );
}
