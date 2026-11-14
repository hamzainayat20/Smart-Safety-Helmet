# UI design system — "Midnight Signal" (Phases 1–3)

Import one file from any screen:

```dart
import 'presentation/design_system/design_system.dart';
```

Preview every component without Firebase:

```bash
flutter run -t lib/design_system_gallery.dart
```

## Principles

1. **Colour means safety.** The interface is neutral (midnight chrome, light work surface, ink actions). Colour is reserved for safety status.
2. **Never colour alone.** Every status has a colour, an icon and a text label (`StatusChip`).
3. **Honest data.** Missing values read "Unavailable" and are never shown as normal. Stale values are labelled "Last known value". Unknown counts render "—", never 0.
4. **Readable outdoors.** No text below 14sp (NFR-US-04). Body text meets WCAG AAA (≥ 7:1).
5. **Thumb-friendly.** Interactive controls are ≥ 48dp, on an 8-point spacing grid.

## Tokens (`app_tokens.dart`)

| Group | Values |
| --- | --- |
| Chrome | `ink #0B1221`, `inkRaised #131C2E`, `inkBorder #26334A`, text `onInk #F5F7FA`, `onInkMuted #B4BFCF` |
| Surface | `canvas #EEF1F5`, `surface #FFFFFF`, `border #DFE4EB`, control border `#7A8599` |
| Text | `textPrimary #0B1221` (18.7:1), `textSecondary #3E4859` (9.2:1) |
| Actions | primary = ink fill / white text; `interactive #1F48D6` for links and focus |
| Brand | `brand #FFC20E` — logo only, never status |
| Spacing | 4 (optical only), 8, 16, 24, 32, 48 |
| Radius | 8 controls · 12 cards · 16 sheets |
| Type | display 32 · headline 24 · title 20 · subtitle 18 · body 16 · label/caption/overline 14 · metric 24 (tabular) |

## Safety status roles (`safety_status.dart`)

| Status | Meaning | Icon | Strong | Text on tint |
| --- | --- | --- | --- | --- |
| normal | within safe limits (FR-MD-03 green) | check_circle | `#039855` | `#05603A` |
| warning | approaching threshold (FR-MD-03 yellow) | warning_amber | `#A16207` | `#713F12` |
| critical | threshold exceeded / sensor fault (red) | error | `#D92D20` | `#912018` |
| offline | connection lost (FR-MD-04) | wifi_off | `#475467` | `#1D2939` |
| stale | last-known value, not live | history | `#0E7490` | `#164E63` |
| pending | loading, warm-up, assessment running | hourglass_top | `#2563EB` | `#1E3A8A` |
| unknown | safety cannot be determined | help_outline | `#667085` | `#344054` |

Use `strong` for icons, rails and gauges on light surfaces (≥ 3:1), `text`/`tint`/`line` for chips and banners (AAA), and `onInk` on the dark chrome (AAA).

Mappings: `safetyStatusForMonitoringState`, `safetyStatusForSeverity`, `safetyStatusForAssessmentRisk`. Only a *safe* state maps to `normal`; access and backend problems map to `unknown`.

## Components (`presentation/components/`)

| Component | Use |
| --- | --- |
| `AppPageHeader`, `ContentSheet`, `HeaderIconButton` | dark header + light work area |
| `AppCard` | every card; optional `status` rail |
| `StatusChip` | status label (icon + text + colour) |
| `SensorCard` + `ThresholdGauge` | one sensor channel with unit, status, freshness, limits |
| `MetricTile` | summary counts; `onInk` variant for hero panels |
| `StateView` | loading / empty / error / offline / stale / permission-denied |
| `AppButton` | primary / secondary / destructive, 48dp, loading state |
| `SectionHeader`, `KeyValueRow`, `ResponsiveTileGrid`, `BrandMark` | layout helpers |

`MonitoringStatePanel` and `SafetyAssessmentCard` are now built from these components. Their APIs and texts are unchanged.

## Tests

`test/design_system_test.dart` checks:

- contrast ratios and the 14sp floor;
- status distinctness, and that only a safe state ever maps to normal;
- the honesty rules in each component;
- 48dp touch targets;
- gallery rendering at 360dp, at 1280dp, and at 200% text scale.

## Phase 2 — screens ported to the design system

Every screen now composes the shared components; no screen defines its own
colours, font sizes or status pills. No repository, view model, Firebase
path, security rule, Cloud Function or firmware file was changed.

### New presentation helpers
| File | Purpose |
|---|---|
| `presentation/sensor_limits.dart` | `SensorLimits` classifies each reading against the helmet's **live configuration** (`ConfigurationRepository.watchConfiguration`, read-only). Falls back to FYP Table 3.2 only when the configuration is missing or unreadable, and says so (`Default limits (Table 3.2)`). `HelmetLimitsBuilder` streams it into a screen. |
| `presentation/assessment_text.dart` | `describeReasonCode` turns AI reason codes into sentences (FR-AI-09 / NFR-AI-08). Unknown codes are shown in readable form, never hidden. |
| `presentation/formatters.dart` | `formatUtcTimestamp` for audit-grade alert timestamps (FR-AL-01). |
| `presentation/components/` | Added `AuthTextField`/`ResultBanner`, `ConnectionIndicator`, `FilterMenu`, `SegmentedFilter`, `InitialsAvatar`/`IconTile`/`RoleTag`, `AppNavigationBar`/`AppNavigationRail`. |

### Behaviour added (all on existing live data)
- **Adaptive navigation** — bottom bar on phones, navigation rail at ≥ 840 dp; alert badges on Alerts / My Alerts.
- **Supervisor dashboard** — site safety overview (Safe / Attention / At risk / No live data), KPI tiles that show "not available" instead of stale numbers, a "Needs attention" list (open alerts, critical first), tappable worker rows that open live sensor detail.
- **Worker dashboard** — status hero, per-sensor cards with threshold gauges coloured by configured limits, gas warm-up shown as its own state.
- **Helmet management** — search (ID, worker, zone, site) and filters were previously non-functional; they now filter the live list, with an empty state and *Clear filters*.
- **Alert log** — type / status / date filters, UTC timestamps and coordinates on every entry, acknowledge from the list.
- **Alert detail** — lifecycle timeline (Raised → Delivered → Seen → Acknowledged → Closed) from the alert's own timestamps.
- **Sensor detail** — heat index (from the AI assessment's own risk), motion/fall data, GPS fix quality, link state and diagnostics (firmware, sensor faults) that were in the model but never displayed.
- **GPS map** — location list, bottom sheet with "Open live sensor data", honest placeholder when Maps is unavailable.
- **Profile** — notification preference switches now report save failures instead of failing silently.

### Removed (dead or misleading UI)
- "SSO not configured" button on login (did nothing).
- Decorative back arrow on the GPS tab (went nowhere).
- Hard-coded sensor thresholds in widgets.

### Tests
`test/phase2_ui_test.dart` covers threshold classification (defaults and
configured), missing-data honesty, battery limits, reason-code text, UTC
formatting, adaptive navigation at 400 / 1280 dp, helmet search + clear,
and the 14 sp text floor on both dashboards.

### Open decisions (not implemented, need owner approval)
- FR-HM-04 threshold **editing** UI (write path to `/config/helmets`).
- FR-AL-04 CSV export (needs a new package).
- GPS lost timeout: app uses 30 s, report FR-GT-04 says 60 s.
- Physical sensor naming (MQ-7 vs MQ135, MPU6050 vs MPU6500) — confirm against the hardware.

## Phase 3 — interaction redesign (no functional change)

Layout, hierarchy and motion only. Every action reuses an existing backend
call; no repository, view model, rule, function or schema changed.

| Area | Change |
|---|---|
| Worker home | Status band leads with state, meaning and **"What to do now"** (first approved recommendation from the AI assessment; hidden when data is not live). Temperature and gas are primary cards; humidity and battery are compact tiles. A thumb-zone bar holds *View alerts* and *Sensor details* (both open existing screens). Uses a plain scroll view: the section count is fixed, so every reading is always built. |
| Trends | `TrendSparkline` + `HelmetHistoryBuilder` draw recent **real** history from the existing `ReadingRepository.watchHelmetReadings` (read-only, same security rules as live readings). Fewer than two readings → nothing is drawn. Direction is stated in text (Rising / Falling / Steady). Gas trend is hidden while the sensor warms up. Shown on the worker home and sensor detail. |
| Supervisor home | "Needs attention" became **Act now**: each open alert offers *Acknowledge* (same confirmation dialog and `DashboardViewModel.acknowledge` as the alert log, via `presentation/alert_actions.dart`) and *Locate* (existing `MapFocusController.focus`, which already switches to the map tab). |
| Motion (`design_system/motion.dart`) | Status band cross-fades on state change; status chips animate colour; a value briefly highlights when a new reading arrives. All one-shot and **zero-duration when the OS reduce-motion setting is on**. |

Tests: `test/redesign_ui_test.dart` (trend classification, no trend from one
reading, highlight on/off under reduced motion, thumb-zone placement and 48dp
height, both worker actions, supervisor acknowledge confirmation and locate).

### Splash screen redesign
Same timer, same `pushReplacement` to the auth flow, same constructor.
- Brand mark inside concentric signal rings that draw in once; staggered fade-in of wordmark ("SafeHelmet" + hi-vis **PRO** tag) and tagline.
- Capability strip (Environment / Location / AI risk) with hairline dividers.
- Progress bar now fills over the **actual** splash duration instead of a frozen half-filled line; hidden when no duration is set.
- Hi-vis hazard stripe on the bottom edge as the site-safety signature.
- All motion one-shot; final state rendered immediately under reduce motion. Scrolls instead of overflowing on short/landscape screens. The timer is now cancelled on dispose.
- Tests: `test/splash_screen_test.dart`.
