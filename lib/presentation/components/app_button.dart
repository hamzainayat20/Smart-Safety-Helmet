import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';

enum AppButtonVariant {
  /// Ink fill — the one main action on a screen.
  primary,

  /// Outlined — supporting actions.
  secondary,

  /// Outlined in critical red — sign out, irreversible actions.
  destructive,
}

/// 48dp button. While [loading] it is disabled and shows a spinner beside the
/// label, so the action cannot be triggered twice.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool loading;

  /// Fill the available width (typical for thumb-zone actions).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabledAction = loading ? null : onPressed;
    final critical = SafetyStatus.critical.palette;
    final spinnerColor = variant == AppButtonVariant.primary
        ? AppColors.onPrimary
        : AppColors.textPrimary;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox.square(
            dimension: AppSizes.iconMd,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spinnerColor,
            ),
          )
        else if (icon != null)
          Icon(icon, size: AppSizes.iconMd),
        if (loading || icon != null) const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: enabledAction,
        child: content,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: enabledAction,
        child: content,
      ),
      AppButtonVariant.destructive => OutlinedButton(
        onPressed: enabledAction,
        style: OutlinedButton.styleFrom(
          foregroundColor: critical.text,
          side: BorderSide(color: critical.strong),
        ),
        child: content,
      ),
    };
    return SizedBox(
      width: expand ? double.infinity : null,
      height: AppSizes.buttonHeight,
      child: button,
    );
  }
}

/// 48×48 icon action for the dark chrome (sign out, back).
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      foregroundColor: AppColors.onInk,
      backgroundColor: AppColors.inkRaised,
      fixedSize: const Size(AppSizes.touchTarget, AppSizes.touchTarget),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.inkBorder),
      ),
    ),
    icon: Icon(icon, size: AppSizes.iconMd),
  );
}
