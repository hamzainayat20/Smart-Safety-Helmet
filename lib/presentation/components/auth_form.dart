import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';

/// Labelled text field used by the authentication forms.
///
/// The visible label sits above the field (not as a placeholder), so it stays
/// readable while typing and is announced by screen readers.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: AppTypography.label.copyWith(color: AppColors.textPrimary),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onSubmitted: onSubmitted,
        style: AppTypography.body.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(
            icon,
            size: AppSizes.iconMd,
            color: AppColors.textSecondary,
          ),
          suffixIcon: suffix,
        ),
      ),
    ],
  );
}

/// Outcome message for an authentication action. Announced to screen readers.
class ResultBanner extends StatelessWidget {
  const ResultBanner({
    super.key,
    required this.succeeded,
    required this.message,
    this.action,
  });

  final bool succeeded;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final status = succeeded ? SafetyStatus.normal : SafetyStatus.critical;
    final palette = status.palette;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.tint,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  succeeded
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: AppSizes.iconMd,
                  color: palette.text,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.label.copyWith(color: palette.text),
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(alignment: Alignment.centerLeft, child: action!),
            ],
          ],
        ),
      ),
    );
  }
}
