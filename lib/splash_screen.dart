import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'presentation/design_system/design_system.dart';

/// Launch screen. Shows the brand, what the system monitors and real startup
/// progress, then replaces itself with [builder] after [duration].
///
/// All motion is one-shot (never repeating) and is skipped entirely when the
/// platform's reduce-motion setting is on.
class SplashScreen extends StatefulWidget {
  final WidgetBuilder builder;

  /// If null, the splash screen won't automatically navigate away.
  final Duration? duration;

  /// If false, motion is skipped and the screen renders in its final state
  /// (useful for screenshot-exact UI).
  final bool animateLoadingLine;

  const SplashScreen({
    super.key,
    required this.builder,
    this.duration,
    this.animateLoadingLine = true,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _entranceDuration = Duration(milliseconds: 900);

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: _entranceDuration,
  );

  /// Tracks the real splash timer, so the bar never claims progress that is
  /// not happening.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.duration ?? Duration.zero,
  );

  Timer? _timer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final duration = widget.duration;
    if (duration != null) {
      _timer = Timer(duration, () {
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: widget.builder));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final animate = widget.animateLoadingLine && !AppMotion.reduced(context);
    final duration = widget.duration;
    if (!animate) {
      _entrance.value = 1;
      _progress.value = duration == null ? 0 : 1;
      return;
    }
    _entrance.forward();
    if (duration != null && duration > Duration.zero) _progress.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _entrance.dispose();
    _progress.dispose();
    super.dispose();
  }

  Animation<double> _interval(double begin, double end) => CurvedAnimation(
    parent: _entrance,
    curve: Interval(begin, end, curve: AppMotion.enter),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.ink,
    body: Stack(
      children: [
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.xl,
                        ),
                        child: _content(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _HazardStripe(),
        ),
      ],
    ),
  );

  Widget _content() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Spacer(flex: 3),
      Align(
        alignment: Alignment.centerLeft,
        child: _SignalMark(progress: _interval(0, 0.7)),
      ),
      const SizedBox(height: AppSpacing.lg),
      _Reveal(
        animation: _interval(0.15, 0.6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Text(
              'SafeHelmet',
              style: AppTypography.display.copyWith(color: AppColors.onInk),
            ),
            const _ProTag(),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      _Reveal(
        animation: _interval(0.25, 0.7),
        child: Text(
          'Live safety monitoring for every worker on site.',
          style: AppTypography.subtitle.copyWith(color: AppColors.onInkMuted),
        ),
      ),
      const Spacer(flex: 4),
      _Reveal(
        animation: _interval(0.4, 0.85),
        child: const _CapabilityStrip(),
      ),
      const SizedBox(height: AppSpacing.lg),
      _Reveal(
        animation: _interval(0.5, 1),
        child: _StartupProgress(
          progress: _progress,
          showBar: widget.duration != null,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'Version 1.0.0',
        style: AppTypography.caption.copyWith(color: AppColors.onInkMuted),
      ),
    ],
  );
}

/// Fades and lifts [child] in as [animation] runs.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.25),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );
}

/// Brand mark inside concentric signal rings — the helmet "reporting in".
class _SignalMark extends StatelessWidget {
  const _SignalMark({required this.progress});

  final Animation<double> progress;

  static const double _size = 144;
  static const double _mark = 72;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _size,
    height: _size,
    child: AnimatedBuilder(
      animation: progress,
      builder: (context, child) => CustomPaint(
        painter: _SignalRingsPainter(progress: progress.value),
        child: child,
      ),
      child: const Center(child: BrandMark(size: _mark)),
    ),
  );
}

class _SignalRingsPainter extends CustomPainter {
  _SignalRingsPainter({required this.progress});

  final double progress;

  static const int _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    const innerRadius = _SignalMark._mark * 0.62;
    for (var i = 0; i < _rings; i++) {
      // Rings appear from the inside out.
      final start = i / (_rings + 1);
      final local = ((progress - start) / (1 - start)).clamp(0.0, 1.0);
      if (local == 0) continue;
      final target =
          innerRadius + (maxRadius - innerRadius - 1) * (i + 1) / _rings;
      final radius = innerRadius + (target - innerRadius) * local;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Color.lerp(
            AppColors.ink,
            i == 0 ? AppColors.brand : AppColors.inkBorder,
            local,
          )!,
      );
    }
    // A short hi-vis "signal" arc on the outer ring once the rings settle.
    if (progress >= 1) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = AppColors.brand;
      final rect = Rect.fromCircle(center: center, radius: maxRadius - 1);
      canvas.drawArc(rect, -math.pi / 2.6, math.pi / 7, false, arc);
    }
  }

  @override
  bool shouldRepaint(_SignalRingsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// High-contrast product-tier tag on hi-vis yellow.
class _ProTag extends StatelessWidget {
  const _ProTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      'PRO',
      style: AppTypography.overline.copyWith(color: AppColors.ink),
    ),
  );
}

/// What the system monitors, as one bordered strip with hairline dividers.
class _CapabilityStrip extends StatelessWidget {
  const _CapabilityStrip();

  static const _items = [
    (Icons.thermostat_rounded, 'Environment'),
    (Icons.location_on_outlined, 'Location'),
    (Icons.psychology_outlined, 'AI risk'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.inkRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.inkBorder),
    ),
    child: Row(
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0)
            const SizedBox(
              width: 1,
              height: AppSpacing.xxl,
              child: ColoredBox(color: AppColors.inkBorder),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  Icon(
                    _items[i].$1,
                    size: AppSizes.iconLg,
                    color: AppColors.brand,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _items[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: AppColors.onInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Startup label with a bar that fills over the actual splash duration.
class _StartupProgress extends StatelessWidget {
  const _StartupProgress({required this.progress, required this.showBar});

  final Animation<double> progress;
  final bool showBar;

  static const double _barHeight = 4;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Starting up',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Starting up…',
            style: AppTypography.label.copyWith(color: AppColors.onInkMuted),
          ),
          if (showBar) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(_barHeight),
              child: SizedBox(
                height: _barHeight,
                child: ColoredBox(
                  color: AppColors.inkBorder,
                  child: AnimatedBuilder(
                    animation: progress,
                    builder: (context, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress.value,
                        heightFactor: 1,
                        child: const ColoredBox(color: AppColors.onInk),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Hi-vis hazard stripe along the bottom edge — the site-safety signature.
class _HazardStripe extends StatelessWidget {
  const _HazardStripe();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      height: AppSpacing.sm,
      width: double.infinity,
      child: CustomPaint(painter: _HazardStripePainter()),
    ),
  );
}

class _HazardStripePainter extends CustomPainter {
  const _HazardStripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.brand);
    final band = Paint()..color = AppColors.ink;
    const step = AppSpacing.md;
    final h = size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -h; x < size.width + h; x += step * 2) {
      canvas.drawPath(
        Path()
          ..moveTo(x, h)
          ..lineTo(x + h, 0)
          ..lineTo(x + h + step, 0)
          ..lineTo(x + step, h)
          ..close(),
        band,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HazardStripePainter oldDelegate) => false;
}
