import 'maps_runtime_contract.dart';

MapsRuntime createMapsRuntime({required Duration timeout}) =>
    const _NativeMapsRuntime();

final class _NativeMapsRuntime implements MapsRuntime {
  const _NativeMapsRuntime();

  @override
  Future<MapsRuntimeResult> initialize() async =>
      const MapsRuntimeResult.ready();
}
