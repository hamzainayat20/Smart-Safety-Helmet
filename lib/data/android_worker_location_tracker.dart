import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

final class AndroidWorkerLocationTracker implements WorkerLocationTracker {
  AndroidWorkerLocationTracker({required WorkerLocationRepository locations})
    : _locations = locations;

  static const _batteryChannel = MethodChannel(
    'com.example.smart_safety/battery_settings',
  );

  final WorkerLocationRepository _locations;
  final StreamController<WorkerLocationTrackingState> _states =
      StreamController.broadcast();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;
  UserProfile? _actor;
  Helmet? _helmet;
  WorkerLocationTrackingState _state = const WorkerLocationTrackingState(
    WorkerLocationTrackingStatus.idle,
  );

  @override
  WorkerLocationTrackingState get state => _state;

  @override
  Stream<WorkerLocationTrackingState> get states => _states.stream;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _emit(WorkerLocationTrackingStatus status, [String? message]) {
    _state = WorkerLocationTrackingState(status, message: message);
    if (!_states.isClosed) _states.add(_state);
  }

  @override
  Future<void> activate({
    required UserProfile actor,
    required Helmet helmet,
  }) async {
    await deactivate();
    if (!_isAndroid) {
      _emit(WorkerLocationTrackingStatus.unavailable);
      return;
    }
    _actor = actor;
    _helmet = helmet;
    if (!await Geolocator.isLocationServiceEnabled()) {
      _emit(
        WorkerLocationTrackingStatus.serviceDisabled,
        'Turn on device location to share your position.',
      );
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _emit(
        WorkerLocationTrackingStatus.permissionDenied,
        'Location permission is denied. Simulated GPS remains available for demos.',
      );
      return;
    }
    if (permission == LocationPermission.whileInUse) {
      _emit(WorkerLocationTrackingStatus.needsBackgroundExplanation);
      return;
    }
    await _startStream(background: true);
  }

  @override
  Future<void> requestBackgroundAccess() async {
    if (!_isAndroid || _actor == null || _helmet == null) return;
    var permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.whileInUse) {
      await Geolocator.openAppSettings();
      permission = await Geolocator.checkPermission();
    }
    if (permission == LocationPermission.always) {
      await _startStream(background: true);
    } else {
      await _startStream(background: false);
    }
  }

  @override
  Future<void> refreshPermission() async {
    if (!_isAndroid || _actor == null || _helmet == null) return;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) {
      await _startStream(background: true);
    } else if (permission == LocationPermission.whileInUse) {
      await _startStream(background: false);
    }
  }

  Future<void> _startStream({required bool background}) async {
    await _positionSubscription?.cancel();
    const notification = ForegroundNotificationConfig(
      notificationTitle: 'SafeHelmet location sharing',
      notificationText: 'SafeHelmet is sharing your location for safety',
      notificationChannelName: 'Worker safety location',
      enableWakeLock: true,
      setOngoing: true,
    );
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
      intervalDuration: const Duration(seconds: 30),
      foregroundNotificationConfig: background ? notification : null,
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(_publish, onError: _handleError);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_publishCurrentPosition(settings));
    });
    _emit(
      background
          ? WorkerLocationTrackingStatus.background
          : WorkerLocationTrackingStatus.foregroundOnly,
      background
          ? 'Phone GPS is shared while the app is in the background.'
          : 'Foreground location is active. Background updates are not allowed.',
    );
  }

  Future<void> _publishCurrentPosition(LocationSettings settings) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      await _publish(position);
    } on Object {
      _handleError(const FormatException('Location refresh failed'));
    }
  }

  Future<void> _publish(Position position) async {
    final actor = _actor;
    final helmet = _helmet;
    if (actor == null || helmet == null) return;
    try {
      await _locations.writeLocation(
        actor: actor,
        helmet: helmet,
        latitudeDegrees: position.latitude,
        longitudeDegrees: position.longitude,
        accuracyM: position.accuracy,
      );
    } on Object {
      _emit(
        WorkerLocationTrackingStatus.unavailable,
        'The latest phone location could not be uploaded.',
      );
    }
  }

  void _handleError(Object _) => _emit(
    WorkerLocationTrackingStatus.unavailable,
    'Phone GPS updates are currently unavailable.',
  );

  @override
  Future<void> openBatterySettings() async {
    if (_isAndroid) await _batteryChannel.invokeMethod<void>('open');
  }

  @override
  Future<void> deactivate() async {
    await _positionSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _positionSubscription = null;
    _actor = null;
    _helmet = null;
    _emit(WorkerLocationTrackingStatus.idle);
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    _states.close();
  }
}
