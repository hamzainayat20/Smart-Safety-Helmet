// Rough, UNCALIBRATED carbon-monoxide estimate from the MQ-7 raw ADC count.
//
// Display only. This is never sent to the backend, never stored, and never
// used for any safety classification or alert. It exists so a demo can show
// the general size of the MQ-7 response; it is not a CO measurement.
//
// Method (MQ-7 datasheet sensitivity curve, common library fit):
//   1. raw ADC -> pin voltage -> module output voltage (10 k / 20 k divider).
//   2. output voltage -> sensor resistance Rs, relative to the load resistor
//      (Rs/RL = (Vc - Vout) / Vout). The load resistor cancels out below.
//   3. R0 is taken from a clean-air baseline raw count supplied at build time,
//      using the datasheet clean-air ratio Rs/R0 = 27.5.
//   4. ppm = 99.042 * (Rs/R0) ^ -1.518, shown only inside the datasheet's
//      rated 20-2000 ppm range.
//
// Known limits: no reference-gas calibration, no 5 V / 1.4 V heater cycle,
// ESP32 ADC non-linearity near the top of its range, and no temperature or
// humidity compensation. Expect errors of 2x or more.

import 'dart:math' as math;

/// Clean-air raw MQ-7 count measured on this helmet, passed at build time with
/// `--dart-define=SMART_SAFETY_MQ7_CLEAN_AIR_RAW=COUNT`. Empty = not set.
const String mq7CleanAirRawDefine = String.fromEnvironment(
  'SMART_SAFETY_MQ7_CLEAN_AIR_RAW',
);

const int _adcMax = 4095; // ESP32 12-bit ADC.
const double _adcReferenceVolts = 3.3; // Nominal span at 11 dB attenuation.
const double _dividerGain = 1.5; // 10 k top / 20 k bottom: Vout = Vpin * 30/20.
const double _supplyVolts = 5.0; // MQ-7 module supply (Vc).
const double _cleanAirRatio = 27.5; // Datasheet Rs/R0 in clean air.
const double _curveA = 99.042;
const double _curveB = -1.518;
const int _saturationRaw = 4090;

/// Lower and upper ends of the datasheet's rated CO range.
const double mq7RatedMinPpm = 20;
const double mq7RatedMaxPpm = 2000;

enum Mq7EstimateKind {
  /// No clean-air baseline configured for this build.
  noBaseline,

  /// The baseline or the reading cannot be converted (out of electrical range).
  invalidInput,

  /// ADC is at or near its maximum, so the value cannot be trusted.
  saturated,

  /// Below the 20 ppm lower end of the rated range.
  belowRange,

  /// Within the rated range; [Mq7CoEstimate.ppm] is set.
  inRange,

  /// Above the 2000 ppm upper end of the rated range.
  aboveRange,
}

final class Mq7CoEstimate {
  const Mq7CoEstimate._(this.kind, [this.ppm]);

  final Mq7EstimateKind kind;

  /// Rounded estimate; only set when [kind] is [Mq7EstimateKind.inRange].
  final double? ppm;

  /// Short label for the diagnostics row.
  String get label => switch (kind) {
    Mq7EstimateKind.noBaseline => 'Not set up (needs a clean-air baseline)',
    Mq7EstimateKind.invalidInput => 'Cannot estimate from this reading',
    Mq7EstimateKind.saturated => 'Cannot estimate (sensor input at maximum)',
    Mq7EstimateKind.belowRange => 'Below 20 ppm (rated range 20–2000)',
    Mq7EstimateKind.inRange => '≈ ${ppm!.round()} ppm',
    Mq7EstimateKind.aboveRange => 'Above 2000 ppm (out of rated range)',
  };
}

/// Parses the build-time clean-air baseline. Returns null when unset/invalid.
int? parseMq7CleanAirRaw(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0 || parsed >= _saturationRaw) return null;
  return parsed;
}

/// Sensor resistance relative to the load resistor, or null if unconvertible.
double? _relativeRs(int raw) {
  if (raw <= 0 || raw > _adcMax) return null;
  final vOut = raw / _adcMax * _adcReferenceVolts * _dividerGain;
  if (vOut <= 0 || vOut >= _supplyVolts) return null;
  return (_supplyVolts - vOut) / vOut;
}

/// Estimates CO ppm for [raw] given the clean-air baseline [cleanAirRaw].
Mq7CoEstimate estimateMq7Co({required int? raw, required int? cleanAirRaw}) {
  if (cleanAirRaw == null) return const Mq7CoEstimate._(Mq7EstimateKind.noBaseline);
  if (raw == null) return const Mq7CoEstimate._(Mq7EstimateKind.invalidInput);
  if (raw >= _saturationRaw) {
    return const Mq7CoEstimate._(Mq7EstimateKind.saturated);
  }
  final rsClean = _relativeRs(cleanAirRaw);
  final rs = _relativeRs(raw);
  if (rsClean == null || rs == null || rs <= 0) {
    return const Mq7CoEstimate._(Mq7EstimateKind.invalidInput);
  }
  final r0 = rsClean / _cleanAirRatio;
  final ratio = rs / r0;
  final ppm = _curveA * _pow(ratio, _curveB);
  if (!ppm.isFinite) return const Mq7CoEstimate._(Mq7EstimateKind.invalidInput);
  if (ppm < mq7RatedMinPpm) return const Mq7CoEstimate._(Mq7EstimateKind.belowRange);
  if (ppm > mq7RatedMaxPpm) return const Mq7CoEstimate._(Mq7EstimateKind.aboveRange);
  return Mq7CoEstimate._(Mq7EstimateKind.inRange, ppm);
}

double _pow(double base, double exponent) =>
    math.pow(base, exponent).toDouble();
