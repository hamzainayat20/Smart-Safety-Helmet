import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';
import 'app_card.dart';

/// Summary count or value (e.g. "Workers online 4/5").
///
/// A null [value] renders an em dash and is announced as "not available", so
/// an unknown count is never mistaken for zero.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.suffix,
    this.status,
    this.onInk = false,
  });

  final String label;
  final String? value;
  final String? suffix;
  final IconData icon;
  final SafetyStatus? status;

  /// Render for the dark chrome (hero panels) instead of a light card.
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    final palette = status?.palette;
    final iconColor = onInk
        ? (palette?.onInk ?? AppColors.onInkMuted)
        : (palette?.strong ?? AppColors.textSecondary);
    final primary = onInk ? AppColors.onInk : AppColors.textPrimary;
    final secondary = onInk ? AppColors.onInkMuted : AppColors.textSecondary;
    final shownValue = value ?? '—';
    final spoken = value == null
        ? '$label: not available'
        : '$label: $value${suffix ?? ''}';

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: AppSizes.iconMd, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(color: secondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(shownValue, style: AppTypography.metric.copyWith(color: primary)),
            if (value != null && suffix != null)
              Text(
                suffix!,
                style: AppTypography.label.copyWith(
                  color: secondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ],
    );

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: onInk
          ? Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.inkRaised,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.inkBorder),
              ),
              child: body,
            )
          : AppCard(child: body),
    );
  }
}
