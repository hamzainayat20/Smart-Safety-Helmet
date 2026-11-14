import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';

/// Square initials avatar with an optional status dot.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.status,
  });

  final String name;
  final double size;
  final SafetyStatus? status;

  String get initials {
    final parts = name
        .split(' ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();
    return parts.isEmpty ? '?' : parts.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              initials,
              style: AppTypography.label.copyWith(color: AppColors.onInk),
            ),
          ),
          if (status != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: status!.palette.strong,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Leading icon in a tinted square, coloured by [status].
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.status = SafetyStatus.unknown,
    this.size = 40,
  });

  final IconData icon;
  final SafetyStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: status.palette.tint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: status.palette.line),
      ),
      child: Icon(icon, size: size * 0.5, color: status.palette.text),
    ),
  );
}

/// Role label shown next to a user's name on the dark chrome.
class RoleTag extends StatelessWidget {
  const RoleTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 28),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.inkRaised,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.inkBorder),
    ),
    child: Center(
      widthFactor: 1,
      child: Text(
        label.toUpperCase(),
        style: AppTypography.overline.copyWith(color: AppColors.onInkMuted),
      ),
    ),
  );
}
