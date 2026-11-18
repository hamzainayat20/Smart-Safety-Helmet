import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/motion.dart';
import '../design_system/safety_status.dart';

/// Shows where data comes from and whether the backend link is up.
///
/// [connected]: `true` connected, `false` offline, `null` still checking.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({
    super.key,
    required this.sourceLabel,
    required this.connected,
  });

  final String sourceLabel;
  final bool? connected;

  @override
  Widget build(BuildContext context) {
    final status = connected == true
        ? SafetyStatus.normal
        : connected == false
        ? SafetyStatus.offline
        : SafetyStatus.pending;
    final state = connected == true
        ? 'connected'
        : connected == false
        ? 'offline'
        : 'checking';
    final color = status.palette.onInk;
    final duration = AppMotion.of(context, AppMotion.quick);
    return Semantics(
      label: '$sourceLabel, $state',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.enter,
        constraints: const BoxConstraints(minHeight: AppSizes.chipHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.inkRaised,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.inkBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: duration,
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              child: Icon(
                connected == false
                    ? Icons.cloud_off_outlined
                    : connected == null
                    ? Icons.more_horiz_rounded
                    : Icons.circle,
                key: ValueKey(connected),
                size: AppSizes.iconSm,
                color: color,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: AnimatedSwitcher(
                duration: duration,
                child: Text(
                  '$sourceLabel · $state',
                  key: ValueKey(state),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.onInkMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
