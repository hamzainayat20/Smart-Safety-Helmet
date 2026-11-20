# Maps configuration — OpenStreetMap (no key needed)

The live map no longer uses Google Maps. It renders **OpenStreetMap**
tiles through the `flutter_map` package, which is free with **no API
key, no Google Cloud project and no billing account**.

## Run

Nothing to configure — the real map works in every build:

```powershell
flutter run -d chrome --dart-define=USE_DEMO_DATA=true
flutter run -d android --dart-define=USE_DEMO_DATA=true
```

## How it works

- Tiles load from `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
  (see the `TileLayer` in `lib/gps_map_page.dart`). The app identifies
  itself with its package name, as the OSM tile policy asks, and shows
  the required "© OpenStreetMap contributors" attribution on the map.
- Helmet markers are Flutter widgets (state pills), taps open the same
  worker details sheet as before, and focusing a worker or a critical
  incident moves the camera and shows the same title/snippet callout
  the Google info window used to show.
- The schematic preview is still used while the map availability check
  runs and whenever a runtime reports it cannot render (the
  `MapsRuntime` contract in `lib/platform/maps/` is unchanged; the web
  implementation is now ready immediately because there is no
  JavaScript SDK or key to load).

## What was removed

- `google_maps_flutter` dependency (replaced by `flutter_map` +
  `latlong2` in `pubspec.yaml`).
- The Android `com.google.android.geo.API_KEY` manifest entry, the
  `MAPS_API_KEY` gradle property / release-build check in
  `android/app/build.gradle.kts`, and `android/local.properties.example`.
- The `GOOGLE_MAPS_WEB_API_KEY` dart-define and the Google Maps
  JavaScript loader in `lib/platform/maps/maps_runtime_web.dart`.

If a future deployment outgrows the public OSM tile servers, point the
`TileLayer` URL at any OSM-compatible tile host (self-hosted or a paid
provider) — no code changes beyond that one template string.
