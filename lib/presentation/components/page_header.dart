import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';

/// Header on the dark chrome at the top of a primary screen.
///
/// Wrap the screen body in a Scaffold with `backgroundColor: AppColors.ink`
/// and place this above the light content area.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.titleSuffix,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.compact = false,
  });

  final String title;

  /// Short upper-case context line above the title.
  final String? eyebrow;
  final String? subtitle;

  /// Small widget shown after the title (e.g. a role tag).
  final Widget? titleSuffix;
  final Widget? leading;
  final List<Widget> actions;

  /// Optional content under the title (connection indicator, search field).
  final Widget? bottom;

  /// Reduces dark chrome on task-focused secondary screens.
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.md,
      compact ? AppSpacing.xs : AppSpacing.sm,
      AppSpacing.sm,
      compact ? AppSpacing.sm : AppSpacing.md,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Semantics(
                  header: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null)
                        Text(
                          eyebrow!,
                          style: AppTypography.overline.copyWith(
                            color: AppColors.onInkMuted,
                          ),
                        ),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (compact
                                        ? AppTypography.title
                                        : AppTypography.headline)
                                    .copyWith(color: AppColors.onInk),
                          ),
                          ?titleSuffix,
                        ],
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onInkMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            ...actions,
          ],
        ),
        if (bottom != null) ...[
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: bottom!,
          ),
        ],
      ],
    ),
  );
}

/// Light work area under an [AppPageHeader], with a rounded top edge.
class ContentSheet extends StatelessWidget {
  const ContentSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: const BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    child: child,
  );
}
