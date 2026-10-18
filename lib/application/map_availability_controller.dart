import 'package:flutter/foundation.dart';

import '../platform/maps/maps_runtime.dart';

final class MapAvailabilityController extends ChangeNotifier {
  MapAvailabilityController(this._runtime);

  final MapsRuntime _runtime;
  MapsRuntimeResult? _result;
  bool _initializing = false;
  bool _disposed = false;

  MapsRuntimeResult? get result => _result;
  bool get isChecking => _result == null;
  bool get canRenderInteractiveMap => _result?.canRenderInteractiveMap ?? false;

  Future<void> initialize() async {
    if (_initializing || _result != null || _disposed) return;
    _initializing = true;
    try {
      _result = await _runtime.initialize();
    } on Object {
      _result = const MapsRuntimeResult(
        MapsRuntimeStatus.loadFailed,
        message: 'Interactive map initialization failed safely.',
      );
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
