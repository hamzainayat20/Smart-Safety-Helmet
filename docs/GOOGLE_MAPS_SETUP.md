# Google Maps configuration

No Maps credentials are stored in this repository. The application remains usable in keyless development mode and shows a schematic location preview instead of map tiles.

## Run without a key

Web with deterministic demo data:

```powershell
flutter run -d chrome --dart-define=USE_DEMO_DATA=true
```

Android debug mode can also start without a Maps key, but real tiles will remain unavailable:

```powershell
flutter run -d android --dart-define=USE_DEMO_DATA=true
```

## Enable Web Google Maps later

Pass the restricted Web key at build or run time. Do not add it to `web/index.html`.

```powershell
flutter run -d chrome --dart-define=USE_DEMO_DATA=true --dart-define=GOOGLE_MAPS_WEB_API_KEY=<GOOGLE_MAPS_WEB_API_KEY>
```

The Web loader waits for the Maps JavaScript API before constructing the Flutter `GoogleMap`. Restrict the Web key to the approved production origins and the Maps JavaScript API.

## Enable Android Google Maps later

Supply an Android-restricted key through one of these configuration inputs:

1. Gradle property `MAPS_API_KEY`.
2. `MAPS_API_KEY` in the ignored `android/local.properties` file.
3. Environment variable `MAPS_API_KEY`.

Example environment-based run:

```powershell
$env:MAPS_API_KEY='<MAPS_API_KEY>'
flutter run -d android --dart-define=USE_DEMO_DATA=true
```

Restrict the Android key to the final application ID, approved signing-certificate fingerprints, and Maps SDK for Android. The application ID remains `com.example.smart_safety` until its Firebase registration is intentionally migrated.

## Credential safety

- Never commit `GOOGLE_MAPS_WEB_API_KEY` or `MAPS_API_KEY`.
- Never put a Web key directly in source-controlled HTML or Dart source.
- Web keys are delivered to browsers and therefore require strict origin and API restrictions.
- Do not copy keys into screenshots, logs, test fixtures, or issue reports.

## Simulated GPS for demonstrations (no GPS module fitted)

The helmet prototype has no GPS module, so real telemetry correctly shows
**GPS Lost**. For a presentation, a build can place helmets that have no real
fix at one fixed, approved public test coordinate. This is compile-time gated
and **off by default**:

```powershell
$env:GOOGLE_MAPS_WEB_API_KEY = "<your key, never committed>"
flutter run -d chrome --web-port 53033 `
  --dart-define=GOOGLE_MAPS_WEB_API_KEY=$env:GOOGLE_MAPS_WEB_API_KEY `
  --dart-define=SMART_SAFETY_ENABLE_SIMULATED_GPS=true `
  --dart-define=SMART_SAFETY_SIMULATED_LAT=<approved public test latitude> `
  --dart-define=SMART_SAFETY_SIMULATED_LNG=<approved public test longitude>
```

Rules enforced in `lib/application/simulated_gps.dart` and
`GpsMapViewModel`:

- The demo location exists only in the map view model. It is never written to
  Firebase, never attached to a `SensorReading`, and never sent to the
  backend. Signed ingestion and the telemetry contract are unchanged.
- A real GPS fix always takes precedence. Only helmets that are reporting
  telemetry but have no location are placed at the demo location.
- The marker, map badge, worker list, details sheet and header all say
  **Simulated GPS / demo location**. No HDOP or "valid fix" is claimed, and the
  marker colour follows the real telemetry state (stale telemetry shows stale).
- Missing, non-numeric, NaN, infinite, out-of-range and 0,0 coordinates are
  rejected; the map then shows "Simulated GPS not enabled" and keeps GPS Lost.
- Browser geolocation is never requested. Use a public site location (for
  example a university building), never a home address.

Omit the three `SMART_SAFETY_*` defines to return to the honest default.
