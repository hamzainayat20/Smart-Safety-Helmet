import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';

/// Label/value row for records (alert detail, helmet details, profile).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 128,
  });

  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: AppTypography.label.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
