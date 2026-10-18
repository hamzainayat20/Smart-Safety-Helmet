import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'alert_detail_screen.dart';
import 'application/dashboard_view_model.dart';
import 'application/gps_map_view_model.dart';
import 'application/map_availability_controller.dart';
import 'domain/models.dart';
import 'platform/maps/maps_runtime.dart';
import 'presentation/formatters.dart';
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

  @override
  void initState() {
    super.initState();
    _mapViewModel = GpsMapViewModel(dashboard: widget.viewModel);
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
      child: Column(
        children: [
          _buildMapHeader(),
          _buildMapArea(),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF4F6FA),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Worker Locations',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 15),
                  if (_mapViewModel.isLoading)
                    const Center(child: CircularProgressIndicator())
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
                    const Text('No authorized active helmets are available.')
                  else
                    ..._mapViewModel.items.map(
                      (item) => _LocationTile(
                        item: item,
                        onTap: () => _selectWorker(item),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildMapHeader() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.arrow_back, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'GPS Tracking',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            IconButton(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout, color: Colors.white, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Worker Map',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          '${_mapViewModel.items.length} helmets • '
          '${_mapViewModel.positionedItems.length} positioned • '
          '${widget.viewModel.profile.organizationName ?? 'Site unassigned'} • '
          '${_mapViewModel.dataSourceLabel}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _buildMapArea() {
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
      height: 220,
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
              left: 8,
              right: 8,
              top: 8,
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
            right: 10,
            bottom: 8,
            child: _MapSourceBadge(label: _mapViewModel.dataSourceLabel),
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _stateIcon(item.markerState),
                  color: _stateColor(item.markerState),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.workerName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatePill(state: item.markerState),
              ],
            ),
            const SizedBox(height: 14),
            _DetailRow(label: 'Helmet ID', value: item.helmet.helmetId),
            _DetailRow(
              label: 'Sensor status',
              value: widget.viewModel.stateLabelFor(item.helmet),
            ),
            _DetailRow(
              label: 'Freshness',
              value: item.reading == null
                  ? 'No telemetry received'
                  : 'Updated ${formatRelativeTime(item.reading!.serverReceivedAt)}',
            ),
            _DetailRow(label: 'GPS', value: _gpsDescription(item)),
            if (item.activeAlert != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
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
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('View active alert'),
                ),
              ),
              if (_canAcknowledge(item.activeAlert!))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        widget.viewModel.isAcknowledging(
                          item.activeAlert!.alertId,
                        )
                        ? null
                        : () => _confirmAcknowledgement(
                            sheetContext,
                            item.activeAlert!,
                          ),
                    icon:
                        widget.viewModel.isAcknowledging(
                          item.activeAlert!.alertId,
                        )
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.task_alt),
                    label: Text(
                      widget.viewModel.isAcknowledging(
                            item.activeAlert!.alertId,
                          )
                          ? 'Confirming with backend…'
                          : 'Acknowledge alert',
                    ),
                  ),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('No active alert actions for this helmet.'),
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
      decoration: const BoxDecoration(color: Color(0xFF0C2346)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.map_outlined,
                  color: Color(0xFF77A6D7),
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Interactive map unavailable in development mode.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (result.message != null)
                        Text(
                          result.message!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 9,
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
                ? const Center(
                    child: Text(
                      'No valid coordinates available for preview.',
                      style: TextStyle(color: Colors.white60, fontSize: 10),
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
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 9),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Schematic preview — not a real map.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
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
                      foregroundColor: const Color(0xFF77A6D7),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    icon: const Icon(Icons.info_outline, size: 13),
                    label: const Text(
                      'Selected details',
                      style: TextStyle(fontSize: 9),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final x = size.width * index / 4;
      final y = size.height * index / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (final item in items) {
      final center = project(item.location!);
      final selected = focus?.helmetId == item.helmet.helmetId;
      if (selected) {
        canvas.drawCircle(
          center,
          13,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
      canvas.drawCircle(
        center,
        8,
        Paint()..color = _stateColor(item.markerState),
      );
      final label = TextPainter(
        text: TextSpan(
          text:
              '${helmetMapStateSymbol(item.markerState)} ${item.helmet.helmetId}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
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
          ..color = const Color(0xFFEB5757)
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
  GoogleMapController? _controller;
  final Map<HelmetMapState, BitmapDescriptor> _icons = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadIcons());
  }

  @override
  void didUpdateWidget(covariant _RealMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focus != null &&
        widget.focusRevision != oldWidget.focusRevision) {
      unawaited(_applyRequestedFocus());
    }
  }

  Future<void> _loadIcons() async {
    for (final state in HelmetMapState.values) {
      _icons[state] = await _createMarkerIcon(state);
    }
    if (mounted) setState(() {});
  }

  Future<void> _applyRequestedFocus() async {
    final focus = widget.focus;
    final controller = _controller;
    if (focus == null || controller == null) return;
    final target = LatLng(
      focus.location.latitudeDegrees,
      focus.location.longitudeDegrees,
    );
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(target, focus.zoom),
    );
    final markerId = focus.reason == MapFocusReason.criticalIncident
        ? 'incident-${focus.alertId}'
        : focus.helmetId;
    await controller.showMarkerInfoWindow(MarkerId(markerId));
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.focus?.location ?? widget.items.first.location!;
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(first.latitudeDegrees, first.longitudeDegrees),
        zoom: widget.focus?.zoom ?? 15,
      ),
      markers: _markers,
      onMapCreated: (controller) {
        _controller = controller;
        unawaited(_applyRequestedFocus());
      },
      mapType: MapType.normal,
      compassEnabled: true,
      mapToolbarEnabled: false,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  Set<Marker> get _markers {
    final markers = <Marker>{
      for (final item in widget.items)
        Marker(
          markerId: MarkerId(item.helmet.helmetId),
          position: LatLng(
            item.location!.latitudeDegrees,
            item.location!.longitudeDegrees,
          ),
          icon: _icons[item.markerState] ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title:
                '${helmetMapStateSymbol(item.markerState)} ${item.workerName} • ${helmetMapStateLabel(item.markerState)}',
            snippet:
                'Helmet ${item.helmet.helmetId}${item.isLastKnown ? ' • Last Known' : ''}',
          ),
          onTap: () => widget.onSelected(item),
        ),
    };
    final focus = widget.focus;
    if (focus != null &&
        focus.reason == MapFocusReason.criticalIncident &&
        focus.alertId != null) {
      markers.add(
        Marker(
          markerId: MarkerId('incident-${focus.alertId}'),
          position: LatLng(
            focus.location.latitudeDegrees,
            focus.location.longitudeDegrees,
          ),
          icon:
              _icons[HelmetMapState.critical] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 100,
          infoWindow: InfoWindow(
            title: '!! Critical incident',
            snippet: 'Helmet ${focus.helmetId}',
          ),
        ),
      );
    }
    return markers;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

Future<BitmapDescriptor> _createMarkerIcon(HelmetMapState state) async {
  const width = 180.0;
  const height = 58.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final color = _stateColor(state);
  final rect = RRect.fromRectAndRadius(
    const Rect.fromLTWH(2, 2, width - 4, height - 4),
    const Radius.circular(22),
  );
  canvas.drawRRect(rect, Paint()..color = color);
  canvas.drawRRect(
    rect,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4,
  );
  final painter = TextPainter(
    text: TextSpan(
      text: '${helmetMapStateSymbol(state)}  ${helmetMapStateLabel(state)}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w900,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: width - 20);
  painter.paint(
    canvas,
    Offset((width - painter.width) / 2, (height - painter.height) / 2),
  );
  final image = await recorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(
    data!.buffer.asUint8List(),
    width: 90,
    height: 29,
  );
}

String _gpsDescription(HelmetMapItem item) {
  final location = item.location;
  if (location == null) return helmetMapStateLabel(item.markerState);
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

Color _stateColor(HelmetMapState state) => switch (state) {
  HelmetMapState.safe => const Color(0xFF219653),
  HelmetMapState.warning => const Color(0xFFF2994A),
  HelmetMapState.critical => const Color(0xFFEB5757),
  HelmetMapState.stale => const Color(0xFF6B7280),
  HelmetMapState.gpsAcquiring => const Color(0xFF2F80ED),
  HelmetMapState.gpsLost => const Color(0xFF4B5563),
};

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});
  final HelmetMapState state;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: _stateColor(state).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_stateIcon(state), size: 13, color: _stateColor(state)),
        const SizedBox(width: 4),
        Text(
          helmetMapStateLabel(state),
          style: TextStyle(
            color: _stateColor(state),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.item, required this.onTap});
  final HelmetMapItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF0C2346),
            radius: 18,
            child: Text(
              item.workerName.isEmpty ? '?' : item.workerName[0],
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.workerName} • ${item.helmet.helmetId}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                Text(
                  item.location == null
                      ? 'Coordinates unavailable • ${item.helmet.zone ?? 'Zone unavailable'}'
                      : '${formatCoordinates(item.location)} • ${item.helmet.zone ?? 'Zone unavailable'}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      _stateIcon(item.markerState),
                      size: 12,
                      color: _stateColor(item.markerState),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${helmetMapStateLabel(item.markerState)} • ${_gpsDescription(item)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: _stateColor(item.markerState),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: _stateColor(item.markerState)),
        ],
      ),
    ),
  );
}

class _UnpositionedMarker extends StatelessWidget {
  const _UnpositionedMarker({required this.item});
  final HelmetMapItem item;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: _stateColor(item.markerState),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_stateIcon(item.markerState), size: 12, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          '${item.helmet.helmetId} • ${helmetMapStateLabel(item.markerState)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
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
    color: const Color(0xFF0C2346),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 28),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (unpositioned.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: unpositioned
                .map((item) => _UnpositionedMarker(item: item))
                .toList(),
          ),
        ],
      ],
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
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: const Color(0xFF0C2346)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(message),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _MapSourceBadge extends StatelessWidget {
  const _MapSourceBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_done_outlined,
          size: 11,
          color: Colors.lightBlueAccent,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
