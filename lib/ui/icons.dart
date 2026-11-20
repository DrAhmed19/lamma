import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import 'theme.dart';

/// تاج الفائز
class CrownPainter extends CustomPainter {
  CrownPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.85)
      ..lineTo(w * 0.02, h * 0.28)
      ..lineTo(w * 0.3, h * 0.55)
      ..lineTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.7, h * 0.55)
      ..lineTo(w * 0.98, h * 0.28)
      ..lineTo(w * 0.92, h * 0.85)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = alpha(color, 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lighten(color, 0.45), color],
        ).createShader(Offset.zero & s),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.08, h * 0.82, w * 0.92, h * 0.98, Radius.circular(h * 0.05)),
      Paint()..color = darken(color, 0.15),
    );
    for (final p in [Offset(w * 0.02, h * 0.28), Offset(w * 0.5, h * 0.08), Offset(w * 0.98, h * 0.28)]) {
      canvas.drawCircle(p, w * 0.06, Paint()..color = lighten(color, 0.6));
    }
  }

  @override
  bool shouldRepaint(CrownPainter old) => old.color != color;
}

/// شعار لمّة: أربع دوائر ملونة متجمعة
class LogoMarkPainter extends CustomPainter {
  LogoMarkPainter({this.t = 0}) : super();
  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.shortestSide * 0.2;
    final orbit = s.shortestSide * 0.24;
    for (var i = 0; i < 4; i++) {
      final a = -math.pi / 2 + i * math.pi / 2 + t * math.pi * 2;
      final p = c + Offset(math.cos(a), math.sin(a)) * orbit;
      canvas.drawCircle(
        p,
        r * 1.15,
        Paint()
          ..color = alpha(C.players[i], 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
      );
    }
    for (var i = 0; i < 4; i++) {
      final a = -math.pi / 2 + i * math.pi / 2 + t * math.pi * 2;
      final p = c + Offset(math.cos(a), math.sin(a)) * orbit;
      paintDisc(canvas, p, r, C.players[i]);
    }
    canvas.drawCircle(c, r * 0.42, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(LogoMarkPainter old) => old.t != t;
}

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// أيقونة شد الحبل
class TugIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final a = Offset(w * 0.12, h * 0.62), b = Offset(w * 0.88, h * 0.38);
    canvas.drawLine(a, b, _stroke(const Color(0xFF8A6A3D), h * 0.12));
    canvas.drawLine(a, b, _stroke(const Color(0xFFE2BE84), h * 0.08));
    final d = b - a;
    for (var i = 1; i < 10; i++) {
      final p = a + d * (i / 10);
      canvas.drawLine(p + Offset(-h * 0.03, -h * 0.03), p + Offset(h * 0.02, h * 0.04), _stroke(const Color(0xFFA9834D), h * 0.025));
    }
    paintDisc(canvas, a, h * 0.16, C.players[0]);
    paintDisc(canvas, b, h * 0.16, C.players[1]);
    final m = a + d * 0.5;
    canvas.drawCircle(m, h * 0.075, Paint()..color = Colors.white);
    canvas.drawCircle(m, h * 0.045, Paint()..color = const Color(0xFFFFC93C));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// أيقونة ردة الفعل (برق)
class ReactionIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final c = s.center(Offset.zero);
    canvas.drawCircle(c, w * 0.4, Paint()..color = alpha(C.go, 0.18));
    canvas.drawCircle(c, w * 0.4, _stroke(alpha(C.go, 0.7), w * 0.04));
    final bolt = Path()
      ..moveTo(w * 0.56, h * 0.14)
      ..lineTo(w * 0.3, h * 0.55)
      ..lineTo(w * 0.48, h * 0.55)
      ..lineTo(w * 0.42, h * 0.86)
      ..lineTo(w * 0.72, h * 0.42)
      ..lineTo(w * 0.53, h * 0.42)
      ..close();
    canvas.drawPath(
      bolt,
      Paint()
        ..color = alpha(const Color(0xFFFFE066), 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.06),
    );
    canvas.drawPath(
      bolt,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF3B0), Color(0xFFFFC93C)],
        ).createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// أيقونة X-O
class XoIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final g = _stroke(alpha(Colors.white, 0.35), w * 0.035);
    for (final f in [1 / 3, 2 / 3]) {
      canvas.drawLine(Offset(w * f, h * 0.08), Offset(w * f, h * 0.92), g);
      canvas.drawLine(Offset(w * 0.08, h * f), Offset(w * 0.92, h * f), g);
    }
    final x = _stroke(C.players[0], w * 0.075);
    void drawX(Offset c) {
      final r = w * 0.1;
      canvas.drawLine(c + Offset(-r, -r), c + Offset(r, r), x);
      canvas.drawLine(c + Offset(r, -r), c + Offset(-r, r), x);
    }

    drawX(Offset(w / 6, h / 6));
    drawX(Offset(w / 2, h / 2));
    final o = _stroke(C.players[1], w * 0.075);
    canvas.drawCircle(Offset(w * 5 / 6, h / 6), w * 0.1, o);
    canvas.drawCircle(Offset(w / 6, h * 5 / 6), w * 0.1, o);
    canvas.drawLine(Offset(w * 0.1, h * 0.1), Offset(w * 0.9, h * 0.9), _stroke(alpha(Colors.white, 0.9), w * 0.03));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// أيقونة أربعة بالصف
class Connect4Icon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final board = RRect.fromLTRBR(w * 0.04, h * 0.14, w * 0.96, h * 0.92, Radius.circular(w * 0.1));
    canvas.drawRRect(board, Paint()..color = const Color(0xFF2B3D8F));
    const pattern = [
      [-1, -1, -1, -1],
      [-1, 0, -1, -1],
      [1, 0, 0, -1],
      [0, 1, 1, 0],
    ];
    final cw = (w * 0.92) / 4;
    final ch = (h * 0.78) / 4;
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        final p = Offset(w * 0.04 + cw * (c + 0.5), h * 0.14 + ch * (r + 0.5));
        final v = pattern[r][c];
        if (v < 0) {
          canvas.drawCircle(p, cw * 0.34, Paint()..color = const Color(0xFF0E1430));
        } else {
          paintDisc(canvas, p, cw * 0.36, v == 0 ? C.players[0] : C.players[3]);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// أيقونة هوكي الهواء
class HockeyIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final table = RRect.fromLTRBR(w * 0.12, h * 0.04, w * 0.88, h * 0.96, Radius.circular(w * 0.14));
    canvas.drawRRect(table, Paint()..color = alpha(Colors.white, 0.08));
    canvas.drawRRect(table, _stroke(alpha(Colors.white, 0.4), w * 0.025));
    canvas.drawLine(Offset(w * 0.12, h * 0.5), Offset(w * 0.88, h * 0.5), _stroke(alpha(Colors.white, 0.3), w * 0.02));
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.12, _stroke(alpha(Colors.white, 0.3), w * 0.02));
    canvas.drawLine(Offset(w * 0.36, h * 0.04), Offset(w * 0.64, h * 0.04), _stroke(C.players[1], w * 0.05));
    canvas.drawLine(Offset(w * 0.36, h * 0.96), Offset(w * 0.64, h * 0.96), _stroke(C.players[0], w * 0.05));
    paintDisc(canvas, Offset(w * 0.4, h * 0.76), w * 0.15, C.players[0]);
    paintDisc(canvas, Offset(w * 0.6, h * 0.22), w * 0.15, C.players[1]);
    final puck = Offset(w * 0.58, h * 0.52);
    canvas.drawCircle(puck, w * 0.1, Paint()..color = alpha(Colors.white, 0.4)..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.04));
    canvas.drawCircle(puck, w * 0.08, Paint()..color = const Color(0xFF14182B));
    canvas.drawCircle(puck, w * 0.08, _stroke(Colors.white, w * 0.025));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
