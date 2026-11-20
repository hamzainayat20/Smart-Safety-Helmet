import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;

import 'alert_detail_screen.dart';
import 'application/dashboard_view_model.dart';
import 'application/gps_map_view_model.dart';
import 'application/map_availability_controller.dart';
import 'domain/models.dart';
import 'platform/maps/maps_runtime.dart';
import 'presentation/design_system/design_system.dart';
import 'presentation/formatters.dart';
import 'sensor_detail_screen.dart';
import 'user_role.dart';

typedef SafetyMapBuilder =
Widget Function(
    BuildContext context,
    List<HelmetMapItem> positionedItems,
    MapFocusRequest? focus,
    int focusRevision,
    ValueChanged<HelmetMapItem> onSelected,
    );

class GpsMapPage extends StatefulWidget {
  const GpsMapPage({
    super.key,
    required this.viewModel,
    required this.onSignOut,
    required this.focusController,
    this.mapBuilder,
    this.mapsRuntime,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onSignOut;
  final MapFocusController focusController;
  final SafetyMapBuilder? mapBuilder;
  final MapsRuntime? mapsRuntime;

  @override
  State<GpsMapPage> createState() => _GpsMapPageState();
}

class _GpsMapPageState extends State<GpsMapPage> {
  late final GpsMapViewModel _mapViewModel;
  late final MapAvailabilityController _mapAvailability;
  bool _mobileListExpanded = true;

  @override
  void initState() {
    super.initState();
    _mapViewModel = GpsMapViewModel(
      dashboard: widget.viewModel,
      simulatedLocations: widget.viewModel.dependencies.simulatedLocations,
    );
    _mapAvailability = MapAvailabilityController(
      widget.mapsRuntime ?? createPlatformMapsRuntime(),
    );
    unawaited(_mapAvailability.initialize());
  }

  @override
  void dispose() {
    _mapViewModel.dispose();
    _mapAvailability.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      _mapViewModel,
      widget.focusController,
      _mapAvailability,
    ]),
    builder: (context, _) => SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMapHeader(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= kNavigationRailBreakpoint;
                if (wide) {
                  return ColoredBox(
                    color: AppColors.canvas,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              child: _buildMapArea(
                                height: constraints.maxHeight,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          SizedBox(width: 360, child: _buildWorkerList()),
                        ],
                      ),
                    ),
                  );
                }
                return ColoredBox(
                  color: AppColors.canvas,
                  child: Column(
                    children: [
                      Expanded(
                        flex: _mobileListExpanded ? 5 : 9,
                        child: _buildMapArea(height: double.infinity),
                      ),
                      _MobileListHandle(
                        expanded: _mobileListExpanded,
                        positioned: _mapViewModel.positionedItems.length,
                        total: _mapViewModel.items.length,
                        onTap: () => setState(
                              () => _mobileListExpanded = !_mobileListExpanded,
                        ),
                      ),
                      if (_mobileListExpanded)
                        Expanded(flex: 4, child: _buildWorkerList()),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildMapHeader() => AppPageHeader(
    title: 'Worker Map',
    compact: true,
    subtitle:
    '${_mapViewModel.items.length} helmets • '
        '${_mapViewModel.positionedItems.length} positioned'
        '${_mapViewModel.simulationActive ? ' (simulated GPS)' : ''} • '
        '${widget.viewModel.profile.organizationName ?? 'Site unassigned'} • '
        '${_mapViewModel.dataSourceLabel}',
    actions: [
      HeaderIconButton(
        icon: Icons.logout_rounded,
        tooltip: 'Sign out',
        onPressed: widget.onSignOut,
      ),
    ],
  );

  Widget _buildWorkerList() => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.xl,
    ),
    children: [
      if (_mapViewModel.simulationProblem != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _MapMessage(
            icon: Icons.warning_amber_rounded,
            title: 'Simulated GPS not enabled',
            message: _mapViewModel.simulationProblem!,
          ),
        )
      else if (_mapViewModel.simulationActive)
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: _MapMessage(
            icon: Icons.science_outlined,
            title: 'Simulated GPS (demo location)',
            message:
            'No GPS module is fitted. Helmets without a real fix are '
                'shown at a fixed demo location for presentation only. It '
                'is not the worker\'s real position and is never stored.',
          ),
        ),
      if (_mapViewModel.isLoading)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_mapViewModel.permissionDenied)
        const _MapMessage(
          icon: Icons.lock_outline,
          title: 'Location access denied',
          message:
          'Worker locations are unavailable for this account or assignment.',
        )
      else if (_mapViewModel.errorMessage != null)
          _MapMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Location service unavailable',
            message: _mapViewModel.errorMessage!,
          )
        else if (_mapViewModel.items.isEmpty)
            const _MapMessage(
              icon: Icons.location_disabled_outlined,
              title: 'Nothing to track',
              message: 'No authorized active helmets are available.',
            )
          else
            for (final item in _mapViewModel.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _LocationTile(item: item, onTap: () => _selectWorker(item)),
              ),
    ],
  );

  Widget _buildMapArea({required double height}) {
    if (_mapViewModel.permissionDenied) {
      return const _MapPlaceholder(
        icon: Icons.lock_outline,
        text: 'Location permission denied',
      );
    }
    if (_mapViewModel.errorMessage != null) {
      return const _MapPlaceholder(
        icon: Icons.cloud_off_outlined,
        text: 'Map data unavailable',
      );
    }
    if (_mapAvailability.isChecking) {
      return const _MapPlaceholder(
        icon: Icons.map_outlined,
        text: 'Preparing map mode…',
      );
    }
    if (!_mapAvailability.canRenderInteractiveMap) {
      return _DevelopmentMapFallback(
        items: _mapViewModel.items,
        result: _mapAvailability.result!,
        focus: widget.focusController.current,
        onSelected: _selectWorker,
      );
    }
    if (_mapViewModel.positionedItems.isEmpty) {
      return _MapPlaceholder(
        icon: Icons.location_searching,
        text: _mapViewModel.isLoading
            ? 'Loading authorized locations…'
            : 'Waiting for a valid GPS fix',
        unpositioned: _mapViewModel.unpositionedItems,
      );
    }
    final builder = widget.mapBuilder ?? _defaultMapBuilder;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: builder(
              context,
              _mapViewModel.positionedItems,
              widget.focusController.current,
              widget.focusController.revision,
              _selectWorker,
            ),
          ),
          if (_mapViewModel.unpositionedItems.isNotEmpty)
            Positioned(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              top: AppSpacing.sm,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _mapViewModel.unpositionedItems
                      .map((item) => _UnpositionedMarker(item: item))
                      .toList(growable: false),
                ),
              ),
            ),
          Positioned(
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: _MapSourceBadge(label: _mapViewModel.dataSourceLabel),
          ),
          if (_mapViewModel.positionedItems.any(
                (item) => item.isSimulatedLocation,
          ))
            const Positioned(
              left: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: _MapSourceBadge(
                key: Key('simulated-gps-badge'),
                label: 'Simulated GPS — demo location',
              ),
            ),
        ],
      ),
    );
  }

  Widget _defaultMapBuilder(
      BuildContext context,
      List<HelmetMapItem> items,
      MapFocusRequest? focus,
      int focusRevision,
      ValueChanged<HelmetMapItem> onSelected,
      ) => _RealMapSurface(
    items: items,
    focus: focus,
    focusRevision: focusRevision,
    onSelected: onSelected,
  );

  void _selectWorker(HelmetMapItem item) {
    final request = _mapViewModel.focusForWorker(item.helmet.helmetId);
    if (request != null) widget.focusController.focus(request);
    unawaited(_showMarkerDetails(item));
  }

  Future<void> _showMarkerDetails(
      HelmetMapItem item,
      ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InitialsAvatar(
                  name: item.workerName,
                  size: AppSizes.touchTarget,
                  status: _stateStatus(item.markerState),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    item.workerName,
                    style: AppTypography.title.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: _StatePill(state: item.markerState),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(),
            KeyValueRow(label: 'Helmet ID', value: item.helmet.helmetId),
            KeyValueRow(
              label: 'Sensor status',
              value: widget.viewModel.stateLabelFor(item.helmet),
            ),
            KeyValueRow(
              label: 'Freshness',
              value: item.reading == null
                  ? 'No telemetry received'
                  : 'Updated ${formatRelativeTime(item.reading!.serverReceivedAt)}',
            ),
            KeyValueRow(label: 'GPS', value: _gpsDescription(item)),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Open live sensor data',
              icon: Icons.sensors_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SensorDetailScreen(
                      helmetId: item.helmet.helmetId,
                      workerName: item.workerName,
                      viewModel: widget.viewModel,
                    ),
                  ),
                );
              },
            ),
            if (item.activeAlert != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'View active alert',
                icon: Icons.warning_amber_rounded,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AlertDetailScreen(
                        profile: widget.viewModel.profile,
                        alertId: item.activeAlert!.alertId,
                        dependencies: widget.viewModel.dependencies,
                      ),
                    ),
                  );
                },
              ),
              if (_canAcknowledge(item.activeAlert!)) ...[
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label:
                  widget.viewModel.isAcknowledging(
                    item.activeAlert!.alertId,
                  )
                      ? 'Confirming with backend…'
                      : 'Acknowledge alert',
                  icon: Icons.task_alt,
                  variant: AppButtonVariant.secondary,
                  loading: widget.viewModel.isAcknowledging(
                    item.activeAlert!.alertId,
                  ),
                  onPressed: () =>
                      _confirmAcknowledgement(sheetContext, item.activeAlert!),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'No active alert actions for this helmet.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  bool _canAcknowledge(SafetyAlert alert) =>
      widget.viewModel.profile.role == UserRole.supervisor &&
          alert.status != AlertStatus.acknowledged &&
          alert.status != AlertStatus.resolved;

  Future<void> _confirmAcknowledgement(
      BuildContext sheetContext,
      SafetyAlert alert,
      ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acknowledge alert?'),
        content: const Text(
          'Acknowledgement records your identity and does not mark the physical hazard safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.viewModel.acknowledge(alert.alertId);
      if (sheetContext.mounted) Navigator.pop(sheetContext);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The backend did not confirm acknowledgement.'),
        ),
      );
    }
  }
}

class _DevelopmentMapFallback extends StatelessWidget {
  const _DevelopmentMapFallback({
    required this.items,
    required this.result,
    required this.focus,
    required this.onSelected,
  });

  final List<HelmetMapItem> items;
  final MapsRuntimeResult result;
  final MapFocusRequest? focus;
  final ValueChanged<HelmetMapItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final positioned = items.where((item) => item.hasMapPosition).toList();
    return Container(
      height: 250,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.inkRaised,
        border: Border(
          top: BorderSide(color: AppColors.inkBorder),
          bottom: BorderSide(color: AppColors.inkBorder),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.map_outlined,
                  color: AppColors.onInkMuted,
                  size: AppSizes.iconMd,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Interactive map unavailable in development mode.',
                        style: AppTypography.label.copyWith(
                          color: AppColors.onInk,
                        ),
                      ),
                      if (result.message != null)
                        Text(
                          result.message!,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onInkMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: positioned.isEmpty
                ? Center(
              child: Text(
                'No valid coordinates available for preview.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onInkMuted,
                ),
              ),
            )
                : Semantics(
              label:
              'Schematic worker location preview. This is not a real map.',
              child: CustomPaint(
                key: const Key('schematic-map-preview'),
                painter: _SchematicLocationPainter(
                  items: positioned,
                  focus: focus,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Schematic preview — not a real map.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.onInkMuted,
                    ),
                  ),
                ),
                if (positioned.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => onSelected(
                      focus == null
                          ? positioned.first
                          : positioned.firstWhere(
                            (item) => item.helmet.helmetId == focus!.helmetId,
                        orElse: () => positioned.first,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onInk,
                    ),
                    icon: const Icon(Icons.info_outline, size: AppSizes.iconSm),
                    label: const Text('Selected details'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileListHandle extends StatelessWidget {
  const _MobileListHandle({
    required this.expanded,
    required this.positioned,
    required this.total,
    required this.onTap,
  });

  final bool expanded;
  final int positioned;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    child: InkWell(
      onTap: onTap,
      child: Semantics(
        button: true,
        expanded: expanded,
        label: expanded
            ? 'Collapse worker locations'
            : 'Expand worker locations',
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.people_alt_outlined, size: AppSizes.iconMd),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Worker locations',
                  style: AppTypography.bodyStrong,
                ),
              ),
              Text(
                '$positioned/$total with GPS',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SchematicLocationPainter extends CustomPainter {
  const _SchematicLocationPainter({required this.items, required this.focus});

  final List<HelmetMapItem> items;
  final MapFocusRequest? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final locations = [
      ...items.map((item) => item.location!),
      if (focus != null) focus!.location,
    ];
    final minLatitude = locations
        .map((location) => location.latitudeDegrees)
        .reduce((a, b) => a < b ? a : b);
    final maxLatitude = locations
        .map((location) => location.latitudeDegrees)
        .reduce((a, b) => a > b ? a : b);
    final minLongitude = locations
        .map((location) => location.longitudeDegrees)
        .reduce((a, b) => a < b ? a : b);
    final maxLongitude = locations
        .map((location) => location.longitudeDegrees)
        .reduce((a, b) => a > b ? a : b);
    const padding = 30.0;
    final latitudeSpan = maxLatitude - minLatitude;
    final longitudeSpan = maxLongitude - minLongitude;

    Offset project(GPSLocation location) {
      final xRatio = longitudeSpan == 0
          ? 0.5
          : (location.longitudeDegrees - minLongitude) / longitudeSpan;
      final yRatio = latitudeSpan == 0
          ? 0.5
          : (maxLatitude - location.latitudeDegrees) / latitudeSpan;
      return Offset(
        padding + xRatio * (size.width - padding * 2),
        padding / 2 + yRatio * (size.height - padding),
      );
    }

    // Radar-style backdrop: range rings and a crosshair (not a real map).
    final gridPaint = Paint()
      ..color = AppColors.inkBorder
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final middle = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    for (var ring = 1; ring <= 3; ring++) {
      canvas.drawCircle(middle, maxRadius * ring / 3, gridPaint);
    }
    canvas.drawLine(
      Offset(0, middle.dy),
      Offset(size.width, middle.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(middle.dx, 0),
      Offset(middle.dx, size.height),
      gridPaint,
    );

    for (final item in items) {
      final center = project(item.location!);
      final selected = focus?.helmetId == item.helmet.helmetId;
      if (selected) {
        canvas.drawCircle(
          center,
          13,
          Paint()
            ..color = AppColors.onPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
      canvas.drawCircle(
        center,
        8,
        Paint()..color = _stateStatus(item.markerState).palette.onInk,
      );
      final label = TextPainter(
        text: TextSpan(
          text:
          '${helmetMapStateSymbol(item.markerState)} ${item.helmet.helmetId}',
          style: const TextStyle(
            color: AppColors.onPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 90);
      label.paint(canvas, center + const Offset(11, -6));
    }

    if (focus?.reason == MapFocusReason.criticalIncident) {
      final center = project(focus!.location);
      canvas.drawCircle(
        center,
        17,
        Paint()
          ..color = SafetyStatus.critical.palette.onInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SchematicLocationPainter oldDelegate) =>
      oldDelegate.items != items || oldDelegate.focus != focus;
}

class _RealMapSurface extends StatefulWidget {
  const _RealMapSurface({
    required this.items,
    required this.focus,
    required this.focusRevision,
    required this.onSelected,
  });

  final List<HelmetMapItem> items;
  final MapFocusRequest? focus;
  final int focusRevision;
  final ValueChanged<HelmetMapItem> onSelected;

  @override
  State<_RealMapSurface> createState() => _RealMapSurfaceState();
}

class _RealMapSurfaceState extends State<_RealMapSurface> {
  final MapController _controller = MapController();

  @override
  void didUpdateWidget(covariant _RealMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focus != null &&
        widget.focusRevision != oldWidget.focusRevision) {
      _applyRequestedFocus();
    }
  }

  void _applyRequestedFocus() {
    final focus = widget.focus;
    if (focus == null) return;
    _controller.move(
      latlong.LatLng(
        focus.location.latitudeDegrees,
        focus.location.longitudeDegrees,
      ),
      focus.zoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.focus?.location ?? widget.items.first.location!;
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: latlong.LatLng(
              first.latitudeDegrees,
              first.longitudeDegrees,
            ),
            initialZoom: widget.focus?.zoom ?? 15,
            onMapReady: _applyRequestedFocus,
          ),
          children: [
            TileLayer(
              // OpenStreetMap tiles: free, no API key or billing account.
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.smart_safety',
            ),
            MarkerLayer(markers: _markers),
          ],
        ),
        const Positioned(
          right: AppSpacing.sm,
          bottom: AppSpacing.sm,
          child: _MapAttribution(),
        ),
      ],
    );
  }

  List<Marker> get _markers {
    final markers = <Marker>[
      for (final item in widget.items)
        Marker(
          point: latlong.LatLng(
            item.location!.latitudeDegrees,
            item.location!.longitudeDegrees,
          ),
          width: item.isSimulatedLocation ? 184 : 128,
          height: 34,
          child: GestureDetector(
            onTap: () => widget.onSelected(item),
            child: _MarkerPill(
              state: item.markerState,
              simulated: item.isSimulatedLocation,
            ),
          ),
        ),
    ];
    final focus = widget.focus;
    if (focus != null) {
      final callout = _calloutFor(focus);
      if (callout != null) {
        markers.add(
          Marker(
            point: latlong.LatLng(
              focus.location.latitudeDegrees,
              focus.location.longitudeDegrees,
            ),
            width: 248,
            height: 118,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _InfoCallout(title: callout.$1, snippet: callout.$2),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      }
    }
    return markers;
  }

  /// The title/snippet pair the Google-era info window showed for the
  /// focused marker, now rendered as an in-map callout bubble.
  (String, String)? _calloutFor(MapFocusRequest focus) {
    if (focus.reason == MapFocusReason.criticalIncident &&
        focus.alertId != null) {
      return ('!! Critical incident', 'Helmet ${focus.helmetId}');
    }
    for (final item in widget.items) {
      if (item.helmet.helmetId != focus.helmetId) continue;
      return (
      '${helmetMapStateSymbol(item.markerState)} ${item.workerName} • '
          '${helmetMapStateLabel(item.markerState)}',
      'Helmet ${item.helmet.helmetId}'
          '${item.isLastKnown ? ' • Last Known' : ''}'
          '${item.isSimulatedLocation ? ' • Simulated GPS (demo location)' : ''}',
      );
    }
    return null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// The pill-shaped state label pinned at a helmet's position — the widget
/// form of the canvas-drawn bitmap the Google map used.
class _MarkerPill extends StatelessWidget {
  const _MarkerPill({required this.state, required this.simulated});

  final HelmetMapState state;
  final bool simulated;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _stateColor(state),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.onPrimary, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      child: Text(
        '${simulated ? 'DEMO  ' : ''}'
            '${helmetMapStateSymbol(state)}  ${helmetMapStateLabel(state)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.onPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoCallout extends StatelessWidget {
  const _InfoCallout({required this.title, required this.snippet});

  final String title;
  final String snippet;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.inkBorder),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyStrong.copyWith(color: AppColors.onInk),
          ),
          Text(
            snippet,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: AppColors.onInkMuted),
          ),
        ],
      ),
    );
  }
}

/// OpenStreetMap's tile policy requires visible attribution.
class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xB3000000),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          '© OpenStreetMap contributors',
          style: TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
    );
  }
}

String _gpsDescription(HelmetMapItem item) {
  final location = item.location;
  if (location == null) return helmetMapStateLabel(item.markerState);
  if (item.isSimulatedLocation) {
    return 'Simulated GPS • demo location, not from helmet hardware';
  }
  final prefix = location.isLastKnown ? 'Last Known • ' : 'Valid fix • ';
  return '$prefix${formatRelativeTime(location.capturedAt)}';
}

IconData _stateIcon(HelmetMapState state) => switch (state) {
  HelmetMapState.safe => Icons.check_circle_outline,
  HelmetMapState.warning => Icons.warning_amber_rounded,
  HelmetMapState.critical => Icons.crisis_alert,
  HelmetMapState.stale => Icons.schedule,
  HelmetMapState.gpsAcquiring => Icons.location_searching,
  HelmetMapState.gpsLost => Icons.location_off_outlined,
};

SafetyStatus _stateStatus(HelmetMapState state) => switch (state) {
  HelmetMapState.safe => SafetyStatus.normal,
  HelmetMapState.warning => SafetyStatus.warning,
  HelmetMapState.critical => SafetyStatus.critical,
  HelmetMapState.stale => SafetyStatus.stale,
  HelmetMapState.gpsAcquiring => SafetyStatus.pending,
  HelmetMapState.gpsLost => SafetyStatus.offline,
};

/// Marker colour on the (light) OpenStreetMap tiles.
Color _stateColor(HelmetMapState state) => _stateStatus(state).palette.strong;

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});

  final HelmetMapState state;

  @override
  Widget build(BuildContext context) => StatusChip(
    status: _stateStatus(state),
    label: helmetMapStateLabel(state),
  );
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.item, required this.onTap});

  final HelmetMapItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _stateStatus(item.markerState);
    return AppCard(
      onTap: onTap,
      status: status.needsAttention ? status : null,
      child: Row(
        children: [
          InitialsAvatar(
            name: item.workerName.isEmpty ? '?' : item.workerName,
            status: status,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.workerName} • ${item.helmet.helmetId}',
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  item.location == null
                      ? 'Coordinates unavailable • ${item.helmet.zone ?? 'Zone unavailable'}'
                      : '${item.isSimulatedLocation ? 'Demo location ' : ''}'
                      '${formatCoordinates(item.location)} • ${item.helmet.zone ?? 'Zone unavailable'}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(
                      _stateIcon(item.markerState),
                      size: AppSizes.iconSm,
                      color: status.palette.strong,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '${helmetMapStateLabel(item.markerState)} • ${_gpsDescription(item)}',
                        style: AppTypography.label.copyWith(
                          color: status.palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _UnpositionedMarker extends StatelessWidget {
  const _UnpositionedMarker({required this.item});

  final HelmetMapItem item;

  @override
  Widget build(BuildContext context) {
    final status = _stateStatus(item.markerState);
    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: status.palette.onInk),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _stateIcon(item.markerState),
            size: AppSizes.iconSm,
            color: status.palette.onInk,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${item.helmet.helmetId} • ${helmetMapStateLabel(item.markerState)}',
            style: AppTypography.label.copyWith(color: AppColors.onInk),
          ),
        ],
      ),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({
    required this.icon,
    required this.text,
    this.unpositioned = const [],
  });

  final IconData icon;
  final String text;
  final List<HelmetMapItem> unpositioned;

  @override
  Widget build(BuildContext context) => Container(
    height: 220,
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: const BoxDecoration(
      color: AppColors.inkRaised,
      border: Border(
        top: BorderSide(color: AppColors.inkBorder),
        bottom: BorderSide(color: AppColors.inkBorder),
      ),
    ),
    alignment: Alignment.center,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.onInkMuted, size: 32),
          const SizedBox(height: AppSpacing.sm),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.label.copyWith(color: AppColors.onInk),
          ),
          if (unpositioned.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              runSpacing: AppSpacing.sm,
              children: [
                for (final item in unpositioned)
                  _UnpositionedMarker(item: item),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconTile(icon: icon),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyStrong.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MapSourceBadge extends StatelessWidget {
  const _MapSourceBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.inkBorder),
    ),
    child: Text(
      label,
      style: AppTypography.label.copyWith(color: AppColors.onInk),
    ),
  );
}
