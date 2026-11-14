import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';
import '../design_system/motion.dart';

/// Briefly tints the background behind [child] when [value] changes, so a new
/// live reading is noticed. One-shot; skipped on the first build, when either
/// value is missing, and when the platform asks for reduced motion.
class ValueChangeHighlight extends StatefulWidget {
  const ValueChangeHighlight({
    super.key,
    required this.value,
    required this.color,
    required this.child,
  });

  final Object? value;
  final Color color;
  final Widget child;

  @override
  State<ValueChangeHighlight> createState() => _ValueChangeHighlightState();
}

class _ValueChangeHighlightState extends State<ValueChangeHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.highlight,
    value: 1,
  );
  bool _reduced = false;

  @override
  void didUpdateWidget(covariant ValueChangeHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_reduced &&
        oldWidget.value != null &&
        widget.value != null &&
        oldWidget.value != widget.value) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reduced = AppMotion.reduced(context);
    if (_reduced && _controller.value != 1) _controller.value = 1;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final fade = Curves.easeOut.transform(_controller.value);
        final color = Color.lerp(widget.color, widget.color.withAlpha(0), fade);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: child,
        );
      },
    );
  }
}
