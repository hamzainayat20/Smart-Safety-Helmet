import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/safety_status.dart';

/// Flat card on the light work surface: white, 1px hairline, radius 12 and a
/// hairline shadow for subtle depth.
///
/// Pass [status] to draw a 4px status rail on the leading edge. Use it only
/// for content that is about that status, so the rail keeps its meaning.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.status,
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final SafetyStatus? status;
  final Color color;
  final Color borderColor;

  /// Optional label read by screen readers for the whole card.
  final String? semanticLabel;

  static const double railWidth = 4;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    Widget content = Padding(padding: padding, child: child);
    final rail = status;
    if (rail != null) {
      // A positioned rail (not IntrinsicHeight) so children may use
      // LayoutBuilder safely.
      content = Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: railWidth),
            child: content,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: railWidth,
            child: ColoredBox(color: rail.palette.strong),
          ),
        ],
      );
    }
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, child: content),
      ),
    );
    if (semanticLabel != null) {
      card = Semantics(
        container: true,
        button: onTap != null,
        label: semanticLabel,
        child: card,
      );
    }
    return card;
  }
}
