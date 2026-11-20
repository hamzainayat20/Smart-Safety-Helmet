import 'maps_runtime_contract.dart';

MapsRuntime createMapsRuntime({required Duration timeout}) =>
    const _WebMapsRuntime();

/// The map renders OpenStreetMap tiles — plain HTTPS images the map
/// widget loads by itself. There is no JavaScript SDK to inject and no
/// API key to validate, so the web runtime is ready immediately.
///
/// (The Google-era implementation loaded the Maps JavaScript API with a
/// `GOOGLE_MAPS_WEB_API_KEY` and could report missingKey,
/// invalidConfiguration, loadFailed or timedOut. None of those states
/// can occur with keyless tiles; the contract keeps them because the
/// schematic fallback and its tests are built around the same result
/// type on every platform.)
final class _WebMapsRuntime implements MapsRuntime {
  const _WebMapsRuntime();

  @override
  Future<MapsRuntimeResult> initialize() async =>
      const MapsRuntimeResult.ready();
}
