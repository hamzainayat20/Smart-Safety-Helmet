import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';
import 'app_button.dart';
import 'app_card.dart';

/// The non-content states every data screen must handle.
enum StateViewKind { loading, empty, error, offline, stale, permissionDenied }

/// Centred, non-scrolling state message. Safe to place inside a ListView.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel = 'Retry',
  });

  final StateViewKind kind;
  final String title;
  final String message;
  final VoidCallback? onAction;
  final String actionLabel;

  SafetyStatus get _status => switch (kind) {
    StateViewKind.loading => SafetyStatus.pending,
    StateViewKind.offline => SafetyStatus.offline,
    StateViewKind.stale => SafetyStatus.stale,
    StateViewKind.empty ||
    StateViewKind.error ||
    StateViewKind.permissionDenied => SafetyStatus.unknown,
  };

  IconData get _icon => switch (kind) {
    StateViewKind.loading => Icons.hourglass_top_rounded,
    StateViewKind.empty => Icons.inbox_outlined,
    StateViewKind.error => Icons.cloud_off_outlined,
    StateViewKind.offline => Icons.wifi_off_rounded,
    StateViewKind.stale => Icons.history_rounded,
    StateViewKind.permissionDenied => Icons.lock_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final palette = _status.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Semantics(
            liveRegion: true,
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: AppSizes.touchTarget,
                    height: AppSizes.touchTarget,
                    decoration: BoxDecoration(
                      color: palette.tint,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: palette.line),
                    ),
                    child: kind == StateViewKind.loading
                        ? Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm + 4),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.strong,
                            ),
                          )
                        : Icon(_icon, size: AppSizes.iconLg, color: palette.text),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTypography.subtitle.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (onAction != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: actionLabel,
                      icon: Icons.refresh_rounded,
                      variant: AppButtonVariant.secondary,
                      expand: false,
                      onPressed: onAction,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
