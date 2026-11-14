import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';

/// Dropdown filter chip. The first entry is the "no filter" default; any
/// other selection is shown as active.
///
/// Menu items are addressed by index so `null` can be a real value
/// (PopupMenuButton treats a null value as "cancelled").
class FilterMenu<T> extends StatelessWidget {
  const FilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.entries,
    required this.onSelected,
  });

  final String label;
  final T value;
  final List<(T, String)> entries;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final index = entries.indexWhere((entry) => entry.$1 == value);
    final current = index < 0 ? entries.first.$2 : entries[index].$2;
    final active = index > 0;
    final foreground = active ? AppColors.onInk : AppColors.textPrimary;
    return PopupMenuButton<int>(
      tooltip: '$label filter: $current',
      initialValue: index < 0 ? 0 : index,
      onSelected: (selected) => onSelected(entries[selected].$1),
      itemBuilder: (context) => [
        for (var i = 0; i < entries.length; i++)
          CheckedPopupMenuItem<int>(
            value: i,
            checked: i == index,
            child: Text(entries[i].$2),
          ),
      ],
      child: Container(
        height: AppSizes.touchTarget,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4),
        decoration: BoxDecoration(
          color: active ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: active ? AppColors.ink : AppColors.borderControl,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: AppTypography.caption.copyWith(
                color: active ? AppColors.onInkMuted : AppColors.textSecondary,
              ),
            ),
            Text(current, style: AppTypography.label.copyWith(color: foreground)),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.expand_more_rounded, size: AppSizes.iconMd, color: foreground),
          ],
        ),
      ),
    );
  }
}
