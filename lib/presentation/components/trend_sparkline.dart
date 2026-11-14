import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';

/// Direction of a short series of readings.
enum TrendDirection { rising, falling, steady }

/// Classifies [values] (oldest first). A change smaller than a quarter of the
/// series' own spread counts as steady, so sensor noise is not reported as a
/// trend.
TrendDirection trendDirection(List<double> values) {
  if (values.length < 2) return TrendDirection.steady;
  final delta = values.last - values.first;
  final spread = values.reduce(math.max) - values.reduce(math.min);
  if (spread == 0 || delta.abs() < spread * 0.25) return TrendDirection.steady;
  return delta > 0 ? TrendDirection.rising : TrendDirection.falling;
}

/// Compact line of recent real readings with the warning limit dashed in.
///
/// Draws nothing for fewer than two readings — a trend is never invented
/// from a single value.
class TrendSparkline extends StatelessWidget {
  const TrendSparkline({
    super.key,
    required this.values,
    required this.status,
    this.warningAt,
    this.unit = '',
    this.height = AppSpacing.xl,
  });

  /// Readings, oldest first.
  final List<double> values;
  final SafetyStatus status;
  final double? warningAt;
  final String unit;
  final double height;

  static String directionLabel(TrendDirection direction) =>
      switch (direction) {
        TrendDirection.rising => 'Rising',
        TrendDirection.falling => 'Falling',
        TrendDirection.steady => 'Steady',
      };

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    final direction = trendDirection(values);
    final line = status == SafetyStatus.normal
        ? AppColors.textSecondary
        : status.palette.strong;
    final caption =
        '${directionLabel(direction)} • last ${values.length} readings';
    return Semantics(
      label:
          'Trend: ${directionLabel(direction).toLowerCase()} from '
          '${values.first.toStringAsFixed(1)}$unit to '
          '${values.last.toStringAsFixed(1)}$unit over the last '
          '${values.length} readings',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: CustomPaint(
                painter: _SparklinePainter(
                  values: values,
                  line: line,
                  warningAt: warningAt,
                  warningColor: SafetyStatus.warning.palette.strong,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  switch (direction) {
                    TrendDirection.rising => Icons.trending_up_rounded,
                    TrendDirection.falling => Icons.trending_down_rounded,
                    TrendDirection.steady => Icons.trending_flat_rounded,
                  },
                  size: AppSizes.iconSm,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.line,
    required this.warningAt,
    required this.warningColor,
  });

  final List<double> values;
  final Color line;
  final double? warningAt;
  final Color warningColor;

  static const double _stroke = 2;
  static const double _dotRadius = 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    var low = values.reduce(math.min);
    var high = values.reduce(math.max);
    final warning = warningAt;
    if (warning != null && warning.isFinite) {
      low = math.min(low, warning);
      high = math.max(high, warning);
    }
    var span = high - low;
    if (span == 0) span = 1;
    low -= span * 0.1;
    high += span * 0.1;
    span = high - low;

    final inset = _dotRadius + 1;
    final width = size.width - inset * 2;
    final height = size.height - inset * 2;
    Offset point(int index, double value) => Offset(
      inset + width * index / (values.length - 1),
      inset + height * (1 - (value - low) / span),
    );

    if (warning != null && warning.isFinite) {
      final y = point(0, warning).dy;
      final dash = Paint()
        ..color = warningColor
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 3, size.width), y),
          dash,
        );
      }
    }

    final path = Path()..moveTo(point(0, values.first).dx, point(0, values.first).dy);
    for (var i = 1; i < values.length; i++) {
      final p = point(i, values[i]);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      point(values.length - 1, values.last),
      _dotRadius,
      Paint()..color = line,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.line != line ||
      oldDelegate.warningAt != warningAt ||
      !_sameValues(oldDelegate.values, values);

  static bool _sameValues(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
