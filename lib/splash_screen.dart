import 'dart:async';

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final WidgetBuilder builder;
  /// If null, the splash screen won't automatically navigate away.
  final Duration? duration;
  /// If false, the small loading line stays fixed (useful for screenshot-exact UI).
  final bool animateLoadingLine;

  const SplashScreen({
    super.key,
    required this.builder,
    this.duration,
    this.animateLoadingLine = false,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      value: 0.5,
    );

    if (widget.animateLoadingLine) {
      _progressController.repeat(reverse: false);
    }

    if (widget.duration != null) {
      Timer(widget.duration!, () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: widget.builder),
        );
      });
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const innerBg = Color(0xFF0B1C3A);
    const outerBg = Color(0xFF07152C);
    const subtitleColor = Color(0xFF3E79B7);
    const versionColor = Color(0xFF5B7FAE);
    const iconBg = Color(0xFF2E73B3);

    return Scaffold(
      backgroundColor: outerBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          return Container(
            width: width,
            height: height,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [innerBg, outerBg],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: (width * 0.08).clamp(24.0, 36.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: height * 0.14),
                    _IconBadge(
                      iconBg: iconBg,
                      size: (width * 0.19).clamp(72.0, 92.0),
                    ),
                    SizedBox(height: height * 0.035),
                    Text(
                      'SafeHelmet Pro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: (width * 0.085).clamp(22.0, 34.0),
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: height * 0.008),
                    Text(
                      'IoT Worker Safety Monitoring',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: (width * 0.040).clamp(11.0, 15.0),
                        fontWeight: FontWeight.w500,
                        color: subtitleColor,
                      ),
                    ),
                    const Spacer(),
                    _LoadingIndicator(
                      progress: _progressController,
                      baseWidth: (width * 0.15).clamp(46.0, 66.0),
                      segmentWidth: (width * 0.07).clamp(20.0, 30.0),
                      height: 4.0,
                    ),
                    SizedBox(height: height * 0.025),
                    Text(
                      'v1.0.0 - Secure - Firebase Powered',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: (width * 0.031).clamp(10.0, 12.0),
                        fontWeight: FontWeight.w500,
                        color: versionColor,
                      ),
                    ),
                    SizedBox(height: height * 0.07),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final Color iconBg;
  final double size;

  const _IconBadge({
    required this.iconBg,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final innerRadius = (size * 0.285).clamp(18.0, 28.0);
    final iconSize = (size * 0.50).clamp(30.0, 52.0);
    final bangSize = (size * 0.44).clamp(22.0, 38.0);
    final bangBottom = (size * 0.065).clamp(3.0, 7.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconBg,
        borderRadius: BorderRadius.circular(innerRadius),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            color: iconBg.withOpacity(0.22),
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.shield,
            size: iconSize,
            color: Colors.white,
          ),
          // Small exclamation mark to mimic the "alert/helmet" look.
          Positioned(
            bottom: bangBottom,
            child: Text(
              '!',
              style: TextStyle(
                fontSize: bangSize,
                height: 1.0,
                fontWeight: FontWeight.w800,
                color: Colors.white.withOpacity(0.95),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  final AnimationController progress;
  final double baseWidth;
  final double segmentWidth;
  final double height;

  const _LoadingIndicator({
    required this.progress,
    this.baseWidth = 58.0,
    this.segmentWidth = 26.0,
    this.height = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        // Mimic the small centered "loading line" from the screenshot.
        final t = progress.value; // 0..1
        final maxShift = baseWidth - segmentWidth;
        final dx = maxShift * t;

        return SizedBox(
          height: height,
          width: baseWidth,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: height,
                width: baseWidth,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
              Transform.translate(
                offset: Offset(dx, 0),
                child: Container(
                  height: height,
                  width: segmentWidth,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F80ED),
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

