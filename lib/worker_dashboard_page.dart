import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';
import 'presentation/helmet_history.dart';
import 'presentation/monitoring_state.dart';
import 'presentation/safety_assessment_card.dart';
import 'presentation/sensor_limits.dart';
import 'sensor_detail_screen.dart';

/// Worker home: one status band that says what is happening and what to do,
/// the two acute hazards (temperature, gas) with their recent trend, compact
/// secondary readings, and the main actions in the thumb zone.
class WorkerDashboardPage extends StatelessWidget {
  const WorkerDashboardPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
    this.onOpenAlerts,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  /// Switches to the worker's alerts tab. Hidden when not provided.
  final VoidCallback? onOpenAlerts;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(child: ContentSheet(child: _body(context))),
        ],
      ),
    ),
  );

  Widget _header() => AppPageHeader(
    title: viewModel.profile.displayName,
    titleSuffix: const RoleTag(label: 'Worker'),
    subtitle: 'Site: ${viewModel.profile.organizationName ?? 'Not assigned'}',
    actions: [
      HeaderIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Sign out',
        onPressed: onSignOut,
      ),
    ],
    bottom: Align(
      alignment: Alignment.centerLeft,
      child: ConnectionIndicator(
        sourceLabel: viewModel.dataSourceLabel,
        connected: viewModel.backendConnected,
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (viewModel.loadState == MonitoringState.loading) {
      return const StateView(
        kind: StateViewKind.loading,
        title: 'Loading your helmet',
        message: 'Connecting to your assigned helmet…',
      );
    }
    if (viewModel.loadState == MonitoringState.permissionDenied ||
        viewModel.loadState == MonitoringState.backendError) {
      return MonitoringStatePanel(
        state: viewModel.loadState,
        title: viewModel.loadState == MonitoringState.permissionDenied
            ? 'Monitoring permission denied'
            : 'Monitoring backend unavailable',
        message: viewModel.errorMessage,
        onRetry: viewModel.retry,
      );
    }

    final helmet = viewModel.helmets.firstOrNull;
    final reading = helmet == null
        ? null
        : viewModel.readingFor(helmet.helmetId);
    final assessment = helmet == null
        ? null
        : viewModel.assessmentFor(helmet.helmetId);
    final workerLocation = helmet == null
        ? null
        : viewModel.workerLocationFor(helmet.helmetId);
    final monitoringState = helmet == null
        ? MonitoringState.empty
        : viewModel.monitoringStateFor(helmet);
    final lastUpdate = helmet == null ? null : viewModel.lastUpdateFor(helmet);
    final notLive =
        monitoringState == MonitoringState.stale ||
        monitoringState == MonitoringState.offline;

    // A fixed, short set of sections: a plain scroll view keeps every reading
    // built (and reachable by screen readers) without lazy-list overhead.
    final list = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBand(
            status: safetyStatusForMonitoringState(monitoringState),
            icon: monitoringStateIcon(monitoringState),
            title: helmet == null
                ? 'No helmet assigned'
                : viewModel.stateLabelFor(helmet),
            description: helmet == null
                ? 'Contact your supervisor for an assignment.'
                : monitoringStateDescription(monitoringState),
            // Only approved, backend-issued recommendations; never shown for a
            // reading that is no longer live.
            action: notLive ? null : assessment?.recommendations.firstOrNull,
            footnote: helmet == null
                ? null
                : lastUpdate == null
                ? 'No update has been received'
                : 'Last update ${formatRelativeTime(lastUpdate)} • ${viewModel.dataSourceLabel}',
            facts: helmet == null
                ? const []
                : [
                    'Helmet ${helmet.helmetId}',
                    reading == null
                        ? 'Link unknown'
                        : 'Link ${_connectivityLabel(reading.connectivity)}',
                    formatWorkerLocationStatus(workerLocation),
                  ],
          ),
          if (helmet != null) ...[
            const SizedBox(height: AppSpacing.md),
            SafetyAssessmentCard(
              reading: reading,
              assessment: assessment,
              compact: true,
            ),
            const SizedBox(height: AppSpacing.lg),
            HelmetLimitsBuilder(
              viewModel: viewModel,
              helmetId: helmet.helmetId,
              builder: (context, limits) => HelmetHistoryBuilder(
                viewModel: viewModel,
                helmetId: helmet.helmetId,
                builder: (context, history) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: 'Your Helmet Status • ${helmet.helmetId}',
                      subtitle: limits.sourceLabel,
                    ),
                    ..._readings(reading, notLive, limits, history),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (helmet == null) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        _ActionBar(
          onOpenAlerts: onOpenAlerts,
          openAlerts: viewModel.alerts
              .where((alert) => alert.status != AlertStatus.resolved)
              .length,
          onOpenDetails: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SensorDetailScreen(
                helmetId: helmet.helmetId,
                workerName: viewModel.profile.displayName,
                viewModel: viewModel,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _readings(
    SensorReading? reading,
    bool notLive,
    SensorLimits limits,
    List<SensorReading> history,
  ) {
    SafetyStatus shown(SafetyStatus status) =>
        notLive && reading != null ? SafetyStatus.stale : status;
    String? label(SafetyStatus status) =>
        notLive && reading != null ? null : readingStatusLabel(status);

    final battery = SensorLimits.battery(reading?.batteryPct);
    final humidity = limits.humidity(reading?.humidityPct);
    final temperature = limits.temperature(reading?.temperatureC);
    final warming = reading?.gasWarmUp == true;
    final gas = limits.gas(reading?.gasPpm, warmingUp: warming);

    return [
      ResponsiveTileGrid(
        minTileWidth: 280,
        children: [
          SensorCard(
            label: 'Temperature',
            icon: Icons.thermostat_rounded,
            value: reading?.temperatureC,
            unit: SensorUnit.degreesCelsius,
            status: shown(temperature),
            statusLabel: label(temperature),
            gauge: ThresholdGauge(
              value: reading?.temperatureC,
              max: limits.temperatureCriticalC * 1.2,
              warningAt: limits.temperatureWarningC,
              criticalAt: limits.temperatureCriticalC,
              status: shown(temperature),
              unit: ' °C',
            ),
            trend: TrendSparkline(
              values: trendSeries(history, (r) => r.temperatureC),
              status: shown(temperature),
              warningAt: limits.temperatureWarningC,
              unit: ' °C',
            ),
          ),
          SensorCard(
            label: warming ? 'Gas Level • Warming Up' : 'Gas Level',
            icon: Icons.air_rounded,
            value: reading?.gasPpm,
            unit: SensorUnit.partsPerMillion,
            status: shown(gas),
            statusLabel: label(gas),
            gauge: ThresholdGauge(
              value: warming ? null : reading?.gasPpm,
              max: limits.gasCriticalPpm * 1.5,
              warningAt: limits.gasWarningPpm,
              criticalAt: limits.gasCriticalPpm,
              status: shown(gas),
              unit: ' ppm',
            ),
            // A warming sensor's values are not usable, so no trend either.
            trend: warming
                ? null
                : TrendSparkline(
                    values: trendSeries(
                      history.where((r) => !r.gasWarmUp).toList(),
                      (r) => r.gasPpm,
                    ),
                    status: shown(gas),
                    warningAt: limits.gasWarningPpm,
                    unit: ' ppm',
                  ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _CompactReading(
              label: 'Humidity',
              icon: Icons.water_drop_outlined,
              value: formatMeasurement(
                reading?.humidityPct,
                SensorUnit.percentRelativeHumidity,
              ),
              hasValue: reading?.humidityPct != null,
              status: shown(humidity),
              statusLabel: label(humidity),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _CompactReading(
              label: 'Battery',
              icon: Icons.battery_charging_full_rounded,
              value: formatMeasurement(
                reading?.batteryPct,
                SensorUnit.percent,
                fractionDigits: 0,
              ),
              hasValue: reading?.batteryPct != null,
              status: shown(battery),
              statusLabel: label(battery),
            ),
          ),
        ],
      ),
    ];
  }

  static String _connectivityLabel(ConnectivityStatus status) =>
      switch (status) {
        ConnectivityStatus.online => 'online',
        ConnectivityStatus.degraded => 'degraded',
        ConnectivityStatus.offlineBuffering => 'buffering',
        ConnectivityStatus.offline => 'offline',
      };

}

/// The one thing a worker must read: state, meaning, and the next action.
/// Cross-fades when the state changes (instant under reduced motion).
class _StatusBand extends StatelessWidget {
  const _StatusBand({
    required this.status,
    required this.icon,
    required this.title,
    required this.description,
    required this.facts,
    this.action,
    this.footnote,
  });

  final SafetyStatus status;
  final IconData icon;
  final String title;
  final String description;
  final String? action;
  final String? footnote;
  final List<String> facts;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.standard),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      child: KeyedSubtree(
        key: ValueKey<SafetyStatus>(status),
        child: _content(),
      ),
    ),
  );

  Widget _content() {
    final palette = status.palette;
    return AppCard(
      status: status,
      color: palette.tint,
      borderColor: palette.line,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSpacing.xxl,
                height: AppSpacing.xxl,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: palette.line),
                ),
                child: Icon(icon, size: AppSpacing.xl, color: palette.strong),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.headline.copyWith(color: palette.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            description,
            style: AppTypography.body.copyWith(color: AppColors.textPrimary),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: palette.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.directions_walk_rounded,
                    size: AppSizes.iconLg,
                    color: palette.strong,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recommended action',
                          style: AppTypography.label.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          action!,
                          style: AppTypography.bodyStrong.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              footnote!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final fact in facts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      fact,
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Secondary reading: label, value and status in a short tile.
class _CompactReading extends StatelessWidget {
  const _CompactReading({
    required this.label,
    required this.icon,
    required this.value,
    required this.hasValue,
    required this.status,
    this.statusLabel,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool hasValue;
  final SafetyStatus status;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    // Missing data is never shown as normal.
    final shown = !hasValue && status == SafetyStatus.normal
        ? SafetyStatus.unknown
        : status;
    final chip = !hasValue && statusLabel == null
        ? 'No reading'
        : statusLabel ?? shown.label;
    return AppCard(
      status: shown.needsAttention ? shown : null,
      semanticLabel: '$label, $value, $chip',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppSizes.iconSm, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ValueChangeHighlight(
              value: value,
              color: shown.palette.tint,
              child: Text(
                value,
                style: AppTypography.subtitle.copyWith(
                  color: hasValue
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          StatusChip(status: shown, label: chip),
        ],
      ),
    );
  }
}

/// Primary actions pinned above the navigation bar, in the thumb zone.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onOpenDetails,
    required this.onOpenAlerts,
    required this.openAlerts,
  });

  final VoidCallback onOpenDetails;
  final VoidCallback? onOpenAlerts;
  final int openAlerts;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (onOpenAlerts != null) ...[
            Expanded(
              child: AppButton(
                key: const Key('worker-open-alerts'),
                label: openAlerts == 0
                    ? 'View alerts'
                    : 'View alerts ($openAlerts)',
                icon: Icons.notifications_none_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: onOpenAlerts,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: AppButton(
              key: const Key('worker-open-details'),
              label: 'Sensor details',
              icon: Icons.speed_rounded,
              onPressed: onOpenDetails,
            ),
          ),
        ],
      ),
    ),
  );
}
