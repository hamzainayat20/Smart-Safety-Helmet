import 'package:flutter/widgets.dart';

/// Motion tokens. Every animation is one-shot (never repeating) and collapses
/// to zero duration when the platform's "reduce motion" / "remove animations"
/// setting is on.
abstract final class AppMotion {
  /// Small state changes: chip colour, icon swap.
  static const Duration quick = Duration(milliseconds: 160);

  /// Status changes on larger surfaces.
  static const Duration standard = Duration(milliseconds: 240);

  /// Fade-out of the "value just changed" highlight.
  static const Duration highlight = Duration(milliseconds: 900);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// Whether the user asked the platform to reduce or remove animations.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or [Duration.zero] when motion is reduced.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
