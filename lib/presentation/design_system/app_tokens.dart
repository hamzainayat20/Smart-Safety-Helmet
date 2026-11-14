import 'package:flutter/material.dart';

/// Smart Safety Helmet design tokens — "Midnight Signal".
///
/// Principle: the interface itself is calm and neutral (midnight chrome, light
/// work surface, ink actions) so that colour is reserved for safety status.
/// Status colours live in `safety_status.dart`.
///
/// Every text colour below was measured against the background it is used on
/// and meets WCAG AAA (≥ 7:1). Non-text indicators meet ≥ 3:1.
abstract final class AppColors {
  // Chrome (dark) — headers, navigation, hero panels -------------------------
  static const ink = Color(0xFF0B1221);
  static const inkRaised = Color(0xFF131C2E);
  static const inkBorder = Color(0xFF26334A);

  /// Text on [ink] (17.4:1).
  static const onInk = Color(0xFFF5F7FA);

  /// Secondary text on [ink] (10.1:1) and [inkRaised] (9.2:1).
  static const onInkMuted = Color(0xFFB4BFCF);

  // Work surface (light) -----------------------------------------------------
  static const canvas = Color(0xFFEEF1F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFF7F9FB);

  /// Decorative hairline (card edges, dividers). Not used as a sole indicator.
  static const border = Color(0xFFDFE4EB);

  /// Control boundary (inputs, outlined buttons) — 3.7:1 on white.
  static const borderControl = Color(0xFF7A8599);

  /// Primary text — 18.7:1 on white, 16.5:1 on canvas.
  static const textPrimary = Color(0xFF0B1221);

  /// Secondary text — 9.2:1 on white, 8.1:1 on canvas.
  static const textSecondary = Color(0xFF3E4859);

  // Interaction ---------------------------------------------------------------
  /// Primary action fill (ink) with [onPrimary] text (18.7:1).
  static const primary = ink;
  static const onPrimary = Color(0xFFFFFFFF);

  /// Links, focus rings and selected controls — 7.1:1 on white.
  static const interactive = Color(0xFF1F48D6);

  // Brand ---------------------------------------------------------------------
  /// Hi-vis helmet yellow. Brand mark only — never a status or action colour,
  /// so it can never be confused with a warning.
  static const brand = Color(0xFFFFC20E);

  /// Hairline shadow colour for subtle card depth (never floating shadows).
  static const shadow = Color(0x140B1221);
}

/// Strict 8-point spacing grid. [xs] (4) is for optical icon/text gaps only.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

abstract final class AppSizes {
  /// Minimum interactive target (Android 48dp; satisfies iOS 44pt).
  static const double touchTarget = 48;

  /// Primary call-to-action height.
  static const double buttonHeight = 48;

  /// Bottom navigation height (thumb zone).
  static const double navigationBar = 64;

  /// Status chips are informational, never interactive.
  static const double chipHeight = 32;

  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
}

/// Type scale on the platform system font (Roboto / SF Pro).
///
/// NFR-US-04: no dashboard text below 14sp, so [minimumFontSize] is the floor
/// for every style here and is enforced by tests.
abstract final class AppTypography {
  static const double minimumFontSize = 14;

  static const _tabular = [FontFeature.tabularFigures()];

  static const display = TextStyle(
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    fontFeatures: _tabular,
  );
  static const headline = TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );
  static const title = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w700,
  );
  static const subtitle = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );
  static const bodyStrong = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
  );
  static const label = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );
  static const caption = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
  );

  /// Section eyebrows. Callers pass upper-case text.
  static const overline = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
  );

  /// Sensor values and counts — tabular so live numbers do not jitter.
  static const metric = TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
  );

  static const all = <String, TextStyle>{
    'display': display,
    'headline': headline,
    'title': title,
    'subtitle': subtitle,
    'body': body,
    'bodyStrong': bodyStrong,
    'label': label,
    'caption': caption,
    'overline': overline,
    'metric': metric,
  };
}
