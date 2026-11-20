import 'package:flutter/material.dart';

import 'theme.dart';

/// خلفية التطبيق: تدرج داكن مع إضاءات ناعمة
class LammaBackground extends StatelessWidget {
  const LammaBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(child: CustomPaint(painter: _BgPainter(), size: Size.infinite));
  }
}

class _BgPainter extends CustomPainter {
  const _BgPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151A3A), C.bg, Color(0xFF07090F)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );
    void glow(Offset c, double r, Color col) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [alpha(col, 0.28), alpha(col, 0)]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(s.width * 0.9, s.height * 0.05), s.width * 0.7, C.accent);
    glow(Offset(s.width * 0.05, s.height * 0.35), s.width * 0.55, C.players[1]);
    glow(Offset(s.width * 0.95, s.height * 0.75), s.width * 0.5, C.players[0]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
