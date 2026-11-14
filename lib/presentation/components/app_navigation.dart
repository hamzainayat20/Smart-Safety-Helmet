import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';

/// One top-level destination.
class AppNavItem {
  const AppNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Live count shown on the icon (e.g. open alerts). Zero hides it.
  final int badgeCount;
}

/// Width at which navigation moves from the bottom bar to a side rail.
const double kNavigationRailBreakpoint = 840;

/// Bottom navigation on the dark chrome — 64dp destinations in the thumb zone.
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.ink,
      border: Border(top: BorderSide(color: AppColors.inkBorder)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: AppSizes.navigationBar,
        child: Row(
          children: [
            for (var index = 0; index < items.length; index++)
              Expanded(
                child: _NavDestination(
                  item: items[index],
                  selected: index == currentIndex,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Side navigation for tablets and desktop widths.
class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.ink,
      border: Border(right: BorderSide(color: AppColors.inkBorder)),
    ),
    child: SafeArea(
      right: false,
      child: SizedBox(
        width: 96,
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.md),
            for (var index = 0; index < items.length; index++)
              SizedBox(
                height: 80,
                child: _NavDestination(
                  item: items[index],
                  selected: index == currentIndex,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NavDestination extends StatelessWidget {
  const _NavDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = item.badgeCount;
    final badgeText = count > 99 ? '99+' : '$count';
    final spoken = count > 0 ? '${item.label}, $count open' : item.label;
    return Semantics(
      button: true,
      selected: selected,
      label: spoken,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 56,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.onInk : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: AppSizes.iconLg,
                    color: selected ? AppColors.ink : AppColors.onInkMuted,
                  ),
                ),
                if (count > 0)
                  Positioned(
                    right: 2,
                    top: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: SafetyStatus.critical.palette.strong,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.ink, width: 1.5),
                      ),
                      child: Text(
                        badgeText,
                        style: AppTypography.label.copyWith(
                          color: AppColors.onPrimary,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: selected ? AppColors.onInk : AppColors.onInkMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
