import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/motion.dart';
import '../design_system/safety_status.dart';

/// Informational status label: icon + text + colour, never colour alone.
///
/// Not interactive, so it may be smaller than a touch target.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.label,
    this.onInk = false,
  });

  final SafetyStatus status;

  /// Overrides [SafetyStatusStyle.label], e.g. 'Sensor fault' or 'PENDING'.
  final String? label;

  /// Use on the dark chrome instead of the light surface.
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    final palette = status.palette;
    final text = label ?? status.label;
    final foreground = onInk ? palette.onInk : palette.text;
    return Semantics(
      label: 'Status: $text',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.quick),
        curve: AppMotion.enter,
        constraints: const BoxConstraints(minHeight: AppSizes.chipHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: onInk ? AppColors.inkRaised : palette.tint,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: onInk ? AppColors.inkBorder : palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: AppSizes.iconSm, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
