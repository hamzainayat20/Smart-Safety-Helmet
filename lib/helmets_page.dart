import 'package:flutter/material.dart';

import 'application/dashboard_view_model.dart';
import 'domain/models.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';
import 'presentation/monitoring_state.dart';
import 'presentation/sensor_limits.dart';
import 'sensor_detail_screen.dart';

class HelmetsPage extends StatefulWidget {
  const HelmetsPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;

  @override
  State<HelmetsPage> createState() => _HelmetsPageState();
}

enum HelmetFilter { all, attention, noLiveData }

class _HelmetsPageState extends State<HelmetsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  HelmetFilter _filter = HelmetFilter.all;

  DashboardViewModel get viewModel => widget.viewModel;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _searchController.clear();
    _query = '';
    _filter = HelmetFilter.all;
  });

  bool _matchesFilter(Helmet helmet) {
    final status = safetyStatusForMonitoringState(
      viewModel.monitoringStateFor(helmet),
    );
    return switch (_filter) {
      HelmetFilter.all => true,
      HelmetFilter.attention =>
        status.needsAttention || status == SafetyStatus.pending,
      HelmetFilter.noLiveData =>
        status == SafetyStatus.offline ||
            status == SafetyStatus.stale ||
            status == SafetyStatus.unknown,
    };
  }

  bool _matchesQuery(Helmet helmet) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      helmet.helmetId,
      viewModel.workerNameFor(helmet),
      helmet.zone ?? '',
      viewModel.siteNameFor(helmet),
    ].join(' ').toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) => SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(child: ContentSheet(child: _buildBody())),
        ],
      ),
    ),
  );

  Widget _buildHeader() {
    final active = viewModel.activeHelmets.length;
    return AppPageHeader(
      title: 'Helmet Management',
      compact: true,
      subtitle:
          '${viewModel.helmets.length} registered • $active active • '
          '${viewModel.helmets.length - active} inactive • ${viewModel.dataSourceLabel}',
      actions: [
        HeaderIconButton(
          icon: Icons.logout_rounded,
          tooltip: 'Sign out',
          onPressed: widget.onSignOut,
        ),
      ],
      bottom: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        style: AppTypography.body.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search helmet ID or worker...',
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: AppSizes.iconMd,
            color: AppColors.textSecondary,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _query = '';
                  }),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: AppSizes.iconMd,
                    color: AppColors.textSecondary,
                  ),
                ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (viewModel.loadState == MonitoringState.loading) {
      return const StateView(
        kind: StateViewKind.loading,
        title: 'Loading helmets',
        message: 'Fetching your assigned helmets…',
      );
    }
    if (viewModel.loadState == MonitoringState.permissionDenied ||
        viewModel.loadState == MonitoringState.backendError) {
      return MonitoringStatePanel(
        state: viewModel.loadState,
        title: viewModel.loadState == MonitoringState.permissionDenied
            ? 'Helmet permission denied'
            : 'Helmet backend unavailable',
        message: viewModel.errorMessage,
        onRetry: viewModel.retry,
      );
    }
    if (viewModel.helmets.isEmpty) {
      return const MonitoringStatePanel(
        state: MonitoringState.empty,
        title: 'No assigned helmets',
        message: 'No helmets are assigned to this supervisor.',
      );
    }

    final visible = viewModel.sortedHelmets
        .where((helmet) => _matchesFilter(helmet) && _matchesQuery(helmet))
        .toList(growable: false);
    final filtered = _query.isNotEmpty || _filter != HelmetFilter.all;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        SegmentedFilter<HelmetFilter>(
          values: HelmetFilter.values,
          selected: _filter,
          labelOf: (value) => switch (value) {
            HelmetFilter.all => 'All',
            HelmetFilter.attention => 'Attention',
            HelmetFilter.noLiveData => 'No live data',
          },
          onSelected: (value) => setState(() => _filter = value),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Showing ${visible.length} of ${viewModel.helmets.length}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (filtered)
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(
                  Icons.filter_alt_off_outlined,
                  size: AppSizes.iconMd,
                ),
                label: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (visible.isEmpty)
          StateView(
            kind: StateViewKind.empty,
            title: 'No matching helmets',
            message: 'Try a different helmet ID, worker name or zone.',
            actionLabel: 'Clear filters',
            onAction: _clearFilters,
          )
        else
          ResponsiveTileGrid(
            minTileWidth: 340,
            maxColumns: 2,
            children: [
              for (final helmet in visible)
                _HelmetCard(
                  helmet: helmet,
                  workerName: viewModel.workerNameFor(helmet),
                  siteName: viewModel.siteNameFor(helmet),
                  reading: viewModel.readingFor(helmet.helmetId),
                  stateLabel: viewModel.stateLabelFor(helmet),
                  status: safetyStatusForMonitoringState(
                    viewModel.monitoringStateFor(helmet),
                  ),
                  lastUpdatedAt: viewModel.lastUpdateFor(helmet),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SensorDetailScreen(
                        helmetId: helmet.helmetId,
                        workerName: viewModel.workerNameFor(helmet),
                        viewModel: viewModel,
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _HelmetCard extends StatelessWidget {
  const _HelmetCard({
    required this.helmet,
    required this.workerName,
    required this.siteName,
    required this.reading,
    required this.stateLabel,
    required this.status,
    required this.lastUpdatedAt,
    required this.onOpen,
  });

  final Helmet helmet;
  final String workerName;
  final String siteName;
  final SensorReading? reading;
  final String stateLabel;
  final SafetyStatus status;
  final DateTime? lastUpdatedAt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final battery = reading?.batteryPct;
    final batteryStatus = SensorLimits.battery(battery);
    final updated = lastUpdatedAt;
    return AppCard(
      onTap: onOpen,
      status: status.needsAttention ? status : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: Icons.engineering_outlined, status: status),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Helmet ${helmet.helmetId}',
                      style: AppTypography.bodyStrong.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '$workerName • $siteName • ${helmet.zone ?? 'Zone unavailable'}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      [
                        updated == null
                            ? 'Never updated'
                            : 'Last update ${formatRelativeTime(updated)}',
                        if (helmet.firmwareVersion != null)
                          'FW ${helmet.firmwareVersion}',
                      ].join(' • '),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          StatusChip(status: status, label: stateLabel),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Reading(
                  formatMeasurement(
                    reading?.temperatureC,
                    SensorUnit.degreesCelsius,
                  ),
                  'Temp',
                ),
              ),
              Expanded(
                child: _Reading(
                  formatMeasurement(
                    reading?.humidityPct,
                    SensorUnit.percentRelativeHumidity,
                  ),
                  'Humidity',
                ),
              ),
              Expanded(
                child: _Reading(
                  formatMeasurement(
                    reading?.gasPpm,
                    SensorUnit.partsPerMillion,
                  ),
                  'Gas',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                Icons.battery_std_rounded,
                size: AppSizes.iconSm,
                color: batteryStatus.palette.strong,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                formatMeasurement(
                  battery,
                  SensorUnit.percent,
                  fractionDigits: 0,
                ),
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ThresholdGauge(
                  value: battery?.toDouble(),
                  max: 100,
                  warningAt: SensorLimits.batteryWarningPct.toDouble(),
                  criticalAt: SensorLimits.batteryCriticalPct.toDouble(),
                  status: batteryStatus,
                  unit: '%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: AppTypography.bodyStrong.copyWith(
            color: value == 'Unavailable'
                ? AppColors.textSecondary
                : AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      Text(
        label,
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}
