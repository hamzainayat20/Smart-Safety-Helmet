import 'maps_runtime_contract.dart';
import 'maps_runtime_stub.dart'
    if (dart.library.js_interop) 'maps_runtime_web.dart'
    as implementation;

export 'maps_runtime_contract.dart';

MapsRuntime createPlatformMapsRuntime({
  Duration timeout = const Duration(seconds: 12),
}) => implementation.createMapsRuntime(timeout: timeout);
