import 'package:flutter/material.dart';

import '../design_system/motion.dart';

/// Gives a newly received critical item one restrained pulse.
///
/// The pulse runs only when [signal] changes, never loops, and is removed when
/// the platform requests reduced motion. The child is always visible and
/// interactive, so safety information never waits for animation.
class OneShotAttention extends StatefulWidget {
  const OneShotAttention({
    super.key,
    required this.signal,
    required this.enabled,
    required this.child,
  });

  final Object signal;
  final bool enabled;
  final Widget child;

  @override
  State<OneShotAttention> createState() => _OneShotAttentionState();
}

class _OneShotAttentionState extends State<OneShotAttention>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.attention,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pulse());
  }

  @override
  void didUpdateWidget(covariant OneShotAttention oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && widget.signal != oldWidget.signal) _pulse();
  }

  void _pulse() {
    if (!mounted || !widget.enabled || AppMotion.reduced(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      if (AppMotion.reduced(context)) return child!;
      final wave = 1 - (2 * _controller.value - 1).abs();
      return Transform.scale(scale: 1 + wave * 0.012, child: child);
    },
  );
}
