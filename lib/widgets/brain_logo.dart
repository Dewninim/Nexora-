// Brain Logo Widget - Tharuka Karunarathne
import 'package:flutter/material.dart';
import 'dart:math' as math;

/// A white brain icon drawn with CustomPainter.
/// Use [size] to control width/height.
class BrainLogo extends StatelessWidget {
  final double size;
  const BrainLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.5),
        child: Image.asset(
          'assets/images/neuromathix_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => CustomPaint(painter: _BrainPainter()),
        ),
      ),
    );
  }
}

class _BrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── Left hemisphere ──
    final leftPath = Path();
    // Outer curve of left lobe
    leftPath.moveTo(w * 0.50, h * 0.18);
    leftPath.cubicTo(
      w * 0.38,
      h * 0.05,
      w * 0.08,
      h * 0.08,
      w * 0.08,
      h * 0.38,
    );
    leftPath.cubicTo(
      w * 0.05,
      h * 0.55,
      w * 0.10,
      h * 0.68,
      w * 0.22,
      h * 0.75,
    );
    leftPath.cubicTo(
      w * 0.28,
      h * 0.82,
      w * 0.38,
      h * 0.88,
      w * 0.50,
      h * 0.88,
    );
    canvas.drawPath(leftPath, paint);

    // Left hemisphere folds (sulci)
    final fold1 = Path();
    fold1.moveTo(w * 0.20, h * 0.28);
    fold1.cubicTo(w * 0.28, h * 0.22, w * 0.36, h * 0.26, w * 0.38, h * 0.34);
    canvas.drawPath(fold1, paint..strokeWidth = w * 0.042);

    final fold2 = Path();
    fold2.moveTo(w * 0.12, h * 0.46);
    fold2.cubicTo(w * 0.20, h * 0.40, w * 0.30, h * 0.44, w * 0.32, h * 0.54);
    canvas.drawPath(fold2, paint);

    final fold3 = Path();
    fold3.moveTo(w * 0.15, h * 0.62);
    fold3.cubicTo(w * 0.24, h * 0.56, w * 0.34, h * 0.60, w * 0.36, h * 0.70);
    canvas.drawPath(fold3, paint);

    // ── Right hemisphere ──
    paint.strokeWidth = w * 0.055;
    final rightPath = Path();
    rightPath.moveTo(w * 0.50, h * 0.18);
    rightPath.cubicTo(
      w * 0.62,
      h * 0.05,
      w * 0.92,
      h * 0.08,
      w * 0.92,
      h * 0.38,
    );
    rightPath.cubicTo(
      w * 0.95,
      h * 0.55,
      w * 0.90,
      h * 0.68,
      w * 0.78,
      h * 0.75,
    );
    rightPath.cubicTo(
      w * 0.72,
      h * 0.82,
      w * 0.62,
      h * 0.88,
      w * 0.50,
      h * 0.88,
    );
    canvas.drawPath(rightPath, paint);

    // Right hemisphere folds
    final rfold1 = Path();
    rfold1.moveTo(w * 0.80, h * 0.28);
    rfold1.cubicTo(w * 0.72, h * 0.22, w * 0.64, h * 0.26, w * 0.62, h * 0.34);
    canvas.drawPath(rfold1, paint..strokeWidth = w * 0.042);

    final rfold2 = Path();
    rfold2.moveTo(w * 0.88, h * 0.46);
    rfold2.cubicTo(w * 0.80, h * 0.40, w * 0.70, h * 0.44, w * 0.68, h * 0.54);
    canvas.drawPath(rfold2, paint);

    final rfold3 = Path();
    rfold3.moveTo(w * 0.85, h * 0.62);
    rfold3.cubicTo(w * 0.76, h * 0.56, w * 0.66, h * 0.60, w * 0.64, h * 0.70);
    canvas.drawPath(rfold3, paint);

    // ── Center dividing line (corpus callosum hint) ──
    paint
      ..strokeWidth = w * 0.038
      ..color = Colors.white.withValues(alpha: 0.55);
    final centerLine = Path();
    centerLine.moveTo(w * 0.50, h * 0.22);
    centerLine.lineTo(w * 0.50, h * 0.84);
    canvas.drawPath(centerLine, paint);

    // ── Stem (brain stem) ──
    paint
      ..strokeWidth = w * 0.055
      ..color = Colors.white;
    final stem = Path();
    stem.moveTo(w * 0.42, h * 0.88);
    stem.cubicTo(w * 0.42, h * 0.96, w * 0.58, h * 0.96, w * 0.58, h * 0.88);
    canvas.drawPath(stem, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
