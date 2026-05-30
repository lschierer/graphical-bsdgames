import 'package:flutter/material.dart';

class HangmanPainter extends CustomPainter {
  final int errors;

  const HangmanPainter(this.errors);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final structurePaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final bodyPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Gallows structure (always drawn)
    // Base
    canvas.drawLine(Offset(w * 0.05, h * 0.92), Offset(w * 0.65, h * 0.92), structurePaint);
    // Vertical pole
    canvas.drawLine(Offset(w * 0.20, h * 0.92), Offset(w * 0.20, h * 0.06), structurePaint);
    // Horizontal beam
    canvas.drawLine(Offset(w * 0.20, h * 0.06), Offset(w * 0.58, h * 0.06), structurePaint);
    // Rope
    canvas.drawLine(Offset(w * 0.58, h * 0.06), Offset(w * 0.58, h * 0.17), structurePaint);
    // Brace
    canvas.drawLine(Offset(w * 0.20, h * 0.18), Offset(w * 0.34, h * 0.06), structurePaint);

    // Body parts revealed in order as errors increase
    // Anchor points
    final cx = w * 0.58;
    final headTop = h * 0.17;
    final headR = h * 0.075;
    final headBottom = headTop + headR * 2;
    final shoulderY = headBottom;
    final hipY = headBottom + h * 0.22;
    final armY = headBottom + h * 0.08;

    if (errors >= 1) {
      // Head
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, headTop + headR), width: headR * 2, height: headR * 2),
        bodyPaint,
      );
    }
    if (errors >= 2) {
      // Upper torso
      canvas.drawLine(Offset(cx, shoulderY), Offset(cx, shoulderY + (hipY - shoulderY) * 0.5), bodyPaint);
    }
    if (errors >= 3) {
      // Lower torso
      canvas.drawLine(Offset(cx, shoulderY + (hipY - shoulderY) * 0.5), Offset(cx, hipY), bodyPaint);
    }
    if (errors >= 4) {
      // Left arm
      canvas.drawLine(Offset(cx, armY), Offset(cx - w * 0.12, armY + h * 0.14), bodyPaint);
    }
    if (errors >= 5) {
      // Right arm
      canvas.drawLine(Offset(cx, armY), Offset(cx + w * 0.12, armY + h * 0.14), bodyPaint);
    }
    if (errors >= 6) {
      // Left leg
      canvas.drawLine(Offset(cx, hipY), Offset(cx - w * 0.12, hipY + h * 0.16), bodyPaint);
    }
    if (errors >= 7) {
      // Right leg
      canvas.drawLine(Offset(cx, hipY), Offset(cx + w * 0.12, hipY + h * 0.16), bodyPaint);
    }
  }

  @override
  bool shouldRepaint(HangmanPainter old) => old.errors != errors;
}
