import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';

/// Smart Safety Helmet brand mark: a hard hat on hi-vis yellow.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Smart Safety Helmet',
    image: true,
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.18),
      decoration: BoxDecoration(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: const CustomPaint(painter: _HardHatPainter()),
    ),
  );
}

class _HardHatPainter extends CustomPainter {
  const _HardHatPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = AppColors.ink;
    final dome = Path()
      ..moveTo(w * 0.14, h * 0.72)
      ..cubicTo(w * 0.14, h * 0.30, w * 0.32, h * 0.14, w * 0.5, h * 0.14)
      ..cubicTo(w * 0.68, h * 0.14, w * 0.86, h * 0.30, w * 0.86, h * 0.72)
      ..close();
    canvas.drawPath(dome, fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.70, w, h * 0.16),
        Radius.circular(h * 0.08),
      ),
      fill,
    );
    canvas.drawLine(
      Offset(w * 0.5, h * 0.24),
      Offset(w * 0.5, h * 0.62),
      Paint()
        ..color = AppColors.brand
        ..strokeWidth = w * 0.07
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HardHatPainter oldDelegate) => false;
}
