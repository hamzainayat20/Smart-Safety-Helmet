import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';
import '../formatters.dart';
import 'app_card.dart';
import 'status_chip.dart';
import 'value_highlight.dart';

/// One sensor channel: label, value with unit, status, freshness and an
/// optional [gauge] and [trend].
///
/// Honesty rules enforced here, not left to callers:
/// * a null [value] renders "Unavailable" and can never show as normal;
/// * a [SafetyStatus.stale] reading is labelled as a last-known value;
/// * the update time is shown whenever [updatedAt] is known.
class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.unit,
    required this.status,
    this.fractionDigits = 1,
    this.statusLabel,
    this.updatedAt,
    this.gauge,
    this.trend,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final num? value;
  final SensorUnit unit;
  final SafetyStatus status;
  final int fractionDigits;
  final String? statusLabel;
  final DateTime? updatedAt;
  final Widget? gauge;

  /// Optional recent-history line, e.g. a [TrendSparkline].
  final Widget? trend;
  final VoidCallback? onTap;

  /// The status actually displayed: missing data is never "normal".
  SafetyStatus get effectiveStatus =>
      value == null && status == SafetyStatus.normal
      ? SafetyStatus.unknown
      : status;

  @override
  Widget build(BuildContext context) {
    final shown = effectiveStatus;
    final valueText = formatMeasurement(
      value,
      unit,
      fractionDigits: fractionDigits,
    );
    final chipText = value == null && statusLabel == null
        ? 'No reading'
        : statusLabel ?? shown.label;
    final updated = updatedAt;
    return AppCard(
      onTap: onTap,
      status: shown.needsAttention ? shown : null,
      semanticLabel: '$label, $valueText, $chipText',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppSizes.iconMd, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ValueChangeHighlight(
              value: valueText,
              color: shown.palette.tint,
              child: Text(
                valueText,
                style: AppTypography.metric.copyWith(
                  color: value == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          if (gauge != null) ...[
            const SizedBox(height: AppSpacing.sm),
            gauge!,
          ],
          if (trend != null) ...[
            const SizedBox(height: AppSpacing.sm),
            trend!,
          ],
          const SizedBox(height: AppSpacing.sm),
          StatusChip(status: shown, label: chipText),
          if (shown == SafetyStatus.stale || updated != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              [
                if (shown == SafetyStatus.stale) 'Last known value',
                if (updated != null) 'Updated ${formatRelativeTime(updated)}',
              ].join(' • '),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
