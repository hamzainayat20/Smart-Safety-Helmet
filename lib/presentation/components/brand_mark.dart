import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';

/// Smart Safety brand mark: a protective helmet with a live sensor signal.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Smart Safety',
    image: true,
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.15),
      decoration: BoxDecoration(
        color: AppColors.inkRaised,
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: AppColors.inkBorder),
      ),
      child: const CustomPaint(painter: _SafetySignalPainter()),
    ),
  );
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.onDark = true, this.markSize = 40});

  final bool onDark;
  final double markSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      BrandMark(size: markSize),
      const SizedBox(width: AppSpacing.sm),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Smart Safety',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.subtitle.copyWith(
                color: onDark ? AppColors.onInk : AppColors.textPrimary,
              ),
            ),
            Text(
              'AI-powered helmet monitoring',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: onDark ? AppColors.onInkMuted : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SafetySignalPainter extends CustomPainter {
  const _SafetySignalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = Paint()
      ..color = AppColors.onInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dome = Path()
      ..moveTo(w * 0.12, h * 0.64)
      ..cubicTo(w * 0.15, h * 0.30, w * 0.32, h * 0.15, w * 0.51, h * 0.15)
      ..cubicTo(w * 0.70, h * 0.15, w * 0.84, h * 0.34, w * 0.86, h * 0.64);
    canvas.drawPath(dome, outline);
    canvas.drawLine(
      Offset(w * 0.06, h * 0.68),
      Offset(w * 0.94, h * 0.68),
      outline,
    );
    final signal = Path()
      ..moveTo(w * 0.19, h * 0.84)
      ..lineTo(w * 0.34, h * 0.84)
      ..lineTo(w * 0.42, h * 0.72)
      ..lineTo(w * 0.52, h * 0.93)
      ..lineTo(w * 0.62, h * 0.76)
      ..lineTo(w * 0.70, h * 0.84)
      ..lineTo(w * 0.84, h * 0.84);
    canvas.drawPath(
      signal,
      Paint()
        ..color = AppColors.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.065
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SafetySignalPainter oldDelegate) => false;
}
