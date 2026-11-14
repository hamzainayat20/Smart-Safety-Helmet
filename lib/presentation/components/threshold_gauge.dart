import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';

/// Horizontal gauge placing a reading against warning/critical limits.
///
/// Draws nothing in the fill when [value] is null — a missing reading is
/// never drawn as zero.
class ThresholdGauge extends StatelessWidget {
  const ThresholdGauge({
    super.key,
    required this.value,
    required this.max,
    required this.status,
    this.min = 0,
    this.warningAt,
    this.criticalAt,
    this.unit = '',
  });

  final double? value;
  final double min;
  final double max;
  final double? warningAt;
  final double? criticalAt;
  final SafetyStatus status;
  final String unit;

  static const double _barHeight = 8;

  double _fraction(double v) {
    final span = max - min;
    if (span <= 0) return 0;
    return ((v - min) / span).clamp(0.0, 1.0);
  }

  String _semanticLabel() {
    final current = value;
    final parts = <String>[
      current == null
          ? 'No reading'
          : 'Reading ${current.toStringAsFixed(1)}$unit',
      if (warningAt != null) 'warning at ${warningAt!.toStringAsFixed(1)}$unit',
      if (criticalAt != null)
        'critical at ${criticalAt!.toStringAsFixed(1)}$unit',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: _semanticLabel(),
    child: ExcludeSemantics(
      child: SizedBox(
        height: AppSpacing.md,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 0.0;
            final current = value;
            final fill = current == null ? 0.0 : _fraction(current) * width;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: _barHeight,
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(_barHeight),
                    border: Border.all(color: AppColors.border),
                  ),
                ),
                if (current != null && width > 0)
                  Container(
                    height: _barHeight,
                    width: fill < _barHeight ? _barHeight : fill,
                    decoration: BoxDecoration(
                      color: status.palette.strong,
                      borderRadius: BorderRadius.circular(_barHeight),
                    ),
                  ),
                if (warningAt != null && width > 0)
                  _marker(
                    _fraction(warningAt!) * width,
                    SafetyStatus.warning.palette.strong,
                  ),
                if (criticalAt != null && width > 0)
                  _marker(
                    _fraction(criticalAt!) * width,
                    SafetyStatus.critical.palette.strong,
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _marker(double x, Color color) => Positioned(
    left: (x - 1).clamp(0.0, double.infinity),
    top: 0,
    bottom: 0,
    child: Container(width: 2, color: color),
  );
}
