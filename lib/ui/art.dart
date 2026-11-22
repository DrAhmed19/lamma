import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

// هوية لمّة البصرية = دمج نمطين:
//  09 الفيكتور طبقات العمق: بدون حدود سوداء، تدرجات وظلال بين الطبقات.
//  05 الكارتون التفاعلي: ظل مقطوع (cel-shading)، لمعة حادة، عيون معبّرة وغير متماثلة.

/// ظل بين الطبقات: نسخة غامقة مزاحة من الشكل (بدون blur، يرسم بسرعة).
void layerShadow(Canvas c, Path p, {Offset off = const Offset(0, 2), double a = 0.22, Color? tint}) {
  c.drawPath(p.shift(off), Paint()..color = alpha(tint ?? const Color(0xFF1A0F3A), a));
}

/// تعبئة بتدرج (فاتح من فوق اليسار) + ظل مقطوع من تحت اليمين + لمعة حادة.
void cel(Canvas c, Path p, Color base, {double shade = 0.22, bool shine = true}) {
  final b = p.getBounds();
  c.drawPath(
    p,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [lighten(base, 0.18), base],
      ).createShader(b),
  );
  if (shade > 0) {
    // الظل = الشكل نفسه ناقص نسخة مزاحة منه (هلال تحت يمين)
    final cut = Path.combine(
      PathOperation.difference,
      p,
      p.shift(Offset(-b.width * 0.07, -b.height * 0.09)),
    );
    c.drawPath(cut, Paint()..color = alpha(_cool(darken(base, 0.4)), shade * 1.6));
  }
  if (shine) {
    final r = Rect.fromLTWH(b.left + b.width * 0.16, b.top + b.height * 0.1, b.width * 0.22, b.height * 0.1);
    c.save();
    c.clipPath(p);
    c.drawOval(r, Paint()..color = alpha(Colors.white, 0.55));
    c.restore();
  }
}

// الظل ما يكون أسود؛ ينحرف للبنفسجي/الأزرق
Color _cool(Color c) => Color.lerp(c, const Color(0xFF2A1B6B), 0.35)!;

Path _ov(Offset c, double rx, double ry) => Path()..addOval(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2));

/// عين معبّرة: بياض، بؤبؤ مع لمعتين. [look] اتجاه النظر، [sq] تضييق (غمزة/ضحك).
void _eye(Canvas c, Offset o, double r, {Offset look = Offset.zero, double sq = 1, Color iris = const Color(0xFF241A45)}) {
  final white = _ov(o, r, r * sq);
  layerShadow(c, white, off: Offset(0, r * 0.12), a: 0.18);
  c.drawPath(white, Paint()..color = Colors.white);
  final pc = o + look * r * 0.28;
  c.drawOval(Rect.fromCenter(center: pc, width: r * 1.15, height: r * 1.3 * sq.clamp(0.4, 1)), Paint()..color = iris);
  c.drawCircle(pc + Offset(-r * 0.2, -r * 0.25 * sq), r * 0.2, Paint()..color = Colors.white);
  c.drawCircle(pc + Offset(r * 0.18, r * 0.2 * sq), r * 0.09, Paint()..color = alpha(Colors.white, 0.85));
}

Path _smile(Offset c, double w, double depth, {double tilt = 0}) => Path()
  ..moveTo(c.dx - w / 2, c.dy - tilt)
  ..quadraticBezierTo(c.dx, c.dy + depth * 1.6, c.dx + w / 2, c.dy + tilt)
  ..quadraticBezierTo(c.dx, c.dy + depth * 0.4, c.dx - w / 2, c.dy - tilt)
  ..close();

void _mouth(Canvas c, Offset o, double w, double depth, {double tilt = 0}) {
  final m = _smile(o, w, depth, tilt: tilt);
  c.drawPath(m, Paint()..color = const Color(0xFF3B1531));
  c.save();
  c.clipPath(m);
  c.drawOval(Rect.fromCenter(center: o + Offset(0, depth * 1.2), width: w * 0.55, height: depth * 1.1), Paint()..color = const Color(0xFFFF6B88));
  c.restore();
}

void _cheeks(Canvas c, Offset l, Offset r, double rad, Color col) {
  final p = Paint()..color = alpha(col, 0.5);
  c.drawOval(Rect.fromCenter(center: l, width: rad * 2, height: rad * 1.3), p);
  c.drawOval(Rect.fromCenter(center: r, width: rad * 2, height: rad * 1.3), p);
}

/// أنواع الشخصيات (المفتاح = الإيموجي المحفوظ بالملف الشخصي، حتى السيرفر ما يتغير)
const kMascots = {'🐼': 'panda', '🦊': 'fox', '🦁': 'lion', '🐱': 'cat', '🐸': 'frog', '🐵': 'monkey', '🐯': 'tiger', '🤖': 'robot'};

class MascotPainter extends CustomPainter {
  MascotPainter(this.kind);
  final String kind;

  @override
  void paint(Canvas canvas, Size s) {
    final u = math.min(s.width, s.height);
    canvas.save();
    canvas.translate((s.width - u) / 2, (s.height - u) / 2);
    _draw(canvas, u);
    canvas.restore();
  }

  void _draw(Canvas c, double u) {
    final ctr = Offset(u * 0.5, u * 0.56);
    final head = _ov(ctr, u * 0.4, u * 0.36);
    // ظل أرضي
    c.drawOval(Rect.fromCenter(center: Offset(u * 0.5, u * 0.95), width: u * 0.6, height: u * 0.07), Paint()..color = alpha(const Color(0xFF1A0F3A), 0.25));
    switch (kind) {
      case 'panda':
        _ears(c, u, const Color(0xFF2B2740), const Color(0xFF47406A));
        cel(c, head, const Color(0xFFF4F1FA));
        for (final sgn in [-1.0, 1.0]) {
          final p = Path()..addOval(Rect.fromCenter(center: Offset(u * (0.5 + sgn * 0.17), u * 0.55), width: u * 0.14, height: u * 0.18));
          c.save();
          c.translate(u * 0.5, u * 0.55);
          c.rotate(sgn * -0.35);
          c.translate(-u * 0.5, -u * 0.55);
          c.drawPath(p, Paint()..color = const Color(0xFF2B2740));
          c.restore();
        }
        _face(c, u, eyeY: 0.55, eyeDx: 0.17, nose: const Color(0xFF2B2740), cheek: const Color(0xFFFFA0B8), dark: true);
      case 'fox':
        _ears(c, u, const Color(0xFFFF8A3D), const Color(0xFF4A2A55), pointy: true);
        cel(c, head, const Color(0xFFFF8A3D));
        final muzzle = Path()
          ..moveTo(u * 0.1, u * 0.6)
          ..quadraticBezierTo(u * 0.3, u * 0.5, u * 0.5, u * 0.62)
          ..quadraticBezierTo(u * 0.7, u * 0.5, u * 0.9, u * 0.6)
          ..quadraticBezierTo(u * 0.78, u * 0.9, u * 0.5, u * 0.9)
          ..quadraticBezierTo(u * 0.22, u * 0.9, u * 0.1, u * 0.6)
          ..close();
        c.save();
        c.clipPath(head);
        c.drawPath(muzzle, Paint()..color = const Color(0xFFFFF1DC));
        c.restore();
        _face(c, u, eyeY: 0.5, eyeDx: 0.17, nose: const Color(0xFF3B1531), cheek: const Color(0xFFFF6B88), wink: true);
      case 'lion':
        final mane = _ov(Offset(u * 0.5, u * 0.55), u * 0.47, u * 0.44);
        layerShadow(c, mane, off: Offset(0, u * 0.02));
        cel(c, mane, const Color(0xFFB8641E), shine: false);
        _ears(c, u, const Color(0xFFFFC24A), const Color(0xFFB8641E));
        cel(c, _ov(ctr.translate(0, u * 0.02), u * 0.33, u * 0.31), const Color(0xFFFFC24A));
        _face(c, u, eyeY: 0.53, eyeDx: 0.14, nose: const Color(0xFF6B2E1E), cheek: const Color(0xFFFF8A6B));
      case 'cat':
        _ears(c, u, const Color(0xFFB9A8FF), const Color(0xFFFF9DBA), pointy: true);
        cel(c, head, const Color(0xFFB9A8FF));
        _face(c, u, eyeY: 0.54, eyeDx: 0.17, nose: const Color(0xFFFF6B88), cheek: const Color(0xFFFF9DBA), whiskers: true);
      case 'frog':
        for (final sgn in [-1.0, 1.0]) {
          final b = _ov(Offset(u * (0.5 + sgn * 0.22), u * 0.24), u * 0.17, u * 0.17);
          layerShadow(c, b);
          cel(c, b, const Color(0xFF38D27A));
        }
        cel(c, head, const Color(0xFF38D27A));
        _eye(c, Offset(u * 0.28, u * 0.24), u * 0.115, look: const Offset(0.3, 0.2));
        _eye(c, Offset(u * 0.72, u * 0.24), u * 0.115, look: const Offset(-0.3, 0.2));
        _cheeks(c, Offset(u * 0.2, u * 0.66), Offset(u * 0.8, u * 0.66), u * 0.07, const Color(0xFFFF8FB0));
        _mouth(c, Offset(u * 0.5, u * 0.66), u * 0.5, u * 0.07);
      case 'monkey':
        for (final sgn in [-1.0, 1.0]) {
          final e = _ov(Offset(u * (0.5 + sgn * 0.42), u * 0.55), u * 0.12, u * 0.12);
          layerShadow(c, e);
          cel(c, e, const Color(0xFF9B5A32), shine: false);
          c.drawOval(Rect.fromCenter(center: Offset(u * (0.5 + sgn * 0.42), u * 0.55), width: u * 0.12, height: u * 0.12), Paint()..color = const Color(0xFFFFD2A6));
        }
        cel(c, head, const Color(0xFF9B5A32));
        final face = Path()
          ..addOval(Rect.fromCenter(center: Offset(u * 0.36, u * 0.5), width: u * 0.34, height: u * 0.3))
          ..addOval(Rect.fromCenter(center: Offset(u * 0.64, u * 0.5), width: u * 0.34, height: u * 0.3))
          ..addOval(Rect.fromCenter(center: Offset(u * 0.5, u * 0.7), width: u * 0.5, height: u * 0.3));
        c.drawPath(face, Paint()..color = const Color(0xFFFFD9B0));
        _face(c, u, eyeY: 0.5, eyeDx: 0.14, nose: const Color(0xFF5A2E1E), cheek: const Color(0xFFFF8A6B), noNoseMouth: true);
      case 'tiger':
        _ears(c, u, const Color(0xFFFFA42B), const Color(0xFF6B2E1E));
        cel(c, head, const Color(0xFFFFA42B));
        final stripe = Paint()..color = const Color(0xFF3B1F3A);
        c.save();
        c.clipPath(head);
        for (final sgn in [-1.0, 1.0]) {
          for (var i = 0; i < 3; i++) {
            final y = u * (0.32 + i * 0.1);
            final p = Path()
              ..moveTo(u * (0.5 + sgn * 0.42), y)
              ..lineTo(u * (0.5 + sgn * 0.27), y + u * 0.03)
              ..lineTo(u * (0.5 + sgn * 0.42), y + u * 0.06)
              ..close();
            c.drawPath(p, stripe);
          }
        }
        c.drawPath(Path()..moveTo(u * 0.5, u * 0.2)..lineTo(u * 0.45, u * 0.38)..lineTo(u * 0.55, u * 0.38)..close(), stripe);
        c.drawOval(Rect.fromCenter(center: Offset(u * 0.5, u * 0.74), width: u * 0.5, height: u * 0.28), Paint()..color = const Color(0xFFFFF1DC));
        c.restore();
        _face(c, u, eyeY: 0.52, eyeDx: 0.16, nose: const Color(0xFF3B1531), cheek: const Color(0xFFFF8A6B));
      case 'robot':
        final ant = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(u * 0.48, u * 0.08, u * 0.04, u * 0.12), Radius.circular(u * 0.02)));
        c.drawPath(ant, Paint()..color = const Color(0xFF8E7CFF));
        c.drawCircle(Offset(u * 0.5, u * 0.08), u * 0.045, Paint()..color = const Color(0xFFFF4D6A));
        for (final sgn in [-1.0, 1.0]) {
          final e = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(u * (0.5 + sgn * 0.42), u * 0.56), width: u * 0.1, height: u * 0.22), Radius.circular(u * 0.04));
          c.drawRRect(e, Paint()..color = const Color(0xFF6F5BE0));
        }
        final body = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(u * 0.1, u * 0.2, u * 0.8, u * 0.7), Radius.circular(u * 0.26)));
        layerShadow(c, body, off: Offset(0, u * 0.02));
        cel(c, body, const Color(0xFF38D27A));
        final screen = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(u * 0.2, u * 0.34, u * 0.6, u * 0.38), Radius.circular(u * 0.16)));
        c.drawPath(screen, Paint()..color = const Color(0xFF14283A));
        c.save();
        c.clipPath(screen);
        c.drawOval(Rect.fromLTWH(u * 0.2, u * 0.3, u * 0.6, u * 0.16), Paint()..color = alpha(Colors.white, 0.1));
        c.restore();
        final glow = Paint()..color = const Color(0xFF7CFFC4);
        c.drawOval(Rect.fromCenter(center: Offset(u * 0.37, u * 0.52), width: u * 0.1, height: u * 0.13), glow);
        c.drawOval(Rect.fromCenter(center: Offset(u * 0.63, u * 0.52), width: u * 0.1, height: u * 0.13), glow);
        c.drawPath(Path()..moveTo(u * 0.4, u * 0.62)..quadraticBezierTo(u * 0.5, u * 0.7, u * 0.6, u * 0.62), Paint()..style = PaintingStyle.stroke..strokeWidth = u * 0.03..strokeCap = StrokeCap.round..color = glow.color);
      default:
        cel(c, head, const Color(0xFFFFC93C));
        _face(c, u, eyeY: 0.54, eyeDx: 0.16, nose: const Color(0xFF3B1531), cheek: const Color(0xFFFF8A6B));
    }
  }

  void _ears(Canvas c, double u, Color out, Color inner, {bool pointy = false}) {
    for (final sgn in [-1.0, 1.0]) {
      final cx = u * (0.5 + sgn * 0.27);
      final Path p;
      if (pointy) {
        p = Path()
          ..moveTo(cx - u * 0.14, u * 0.4)
          ..quadraticBezierTo(cx - u * 0.13, u * 0.14, cx + sgn * u * 0.05, u * 0.03)
          ..quadraticBezierTo(cx + u * 0.15, u * 0.16, cx + u * 0.14, u * 0.4)
          ..close();
      } else {
        p = _ov(Offset(cx, u * 0.22), u * 0.13, u * 0.13);
      }
      layerShadow(c, p);
      cel(c, p, out, shine: false);
      final ip = _ov(Offset(cx + (pointy ? sgn * u * 0.01 : 0), u * (pointy ? 0.23 : 0.22)), u * 0.06, u * (pointy ? 0.09 : 0.065));
      c.drawPath(ip, Paint()..color = inner);
    }
  }

  void _face(Canvas c, double u, {required double eyeY, required double eyeDx, required Color nose, required Color cheek, bool wink = false, bool whiskers = false, bool dark = false, bool noNoseMouth = false}) {
    final er = 0.075; // نسبة من u
    // عين أكبر شوية من الثانية (كسر التناظر)
    _eye(c, Offset(u * (0.5 - eyeDx), u * eyeY), u * er * 1.06, look: const Offset(0.25, 0.15));
    if (wink) {
      c.drawPath(
        Path()..moveTo(u * (0.5 + eyeDx) - er, u * eyeY)..quadraticBezierTo(u * (0.5 + eyeDx), u * eyeY + er * 1.1, u * (0.5 + eyeDx) + er, u * eyeY),
        Paint()..style = PaintingStyle.stroke..strokeWidth = u * 0.028..strokeCap = StrokeCap.round..color = const Color(0xFF241A45),
      );
    } else {
      _eye(c, Offset(u * (0.5 + eyeDx), u * eyeY), u * er * 0.96, look: const Offset(0.25, 0.15));
    }
    // حواجب مرفوعة بشكل غير متماثل
    final brow = Paint()..style = PaintingStyle.stroke..strokeWidth = u * 0.026..strokeCap = StrokeCap.round..color = dark ? const Color(0xFF2B2740) : alpha(const Color(0xFF241A45), 0.8);
    if (!dark) c.drawLine(Offset(u * (0.5 - eyeDx - er), u * (eyeY - er * 2.3)), Offset(u * (0.5 - eyeDx + er), u * (eyeY - er * 2.0)), brow);
    if (!dark) c.drawLine(Offset(u * (0.5 + eyeDx - er), u * (eyeY - er * 2.0)), Offset(u * (0.5 + eyeDx + er), u * (eyeY - er * 1.6)), brow);
    _cheeks(c, Offset(u * (0.5 - eyeDx - er * 0.9), u * (eyeY + er * 2.2)), Offset(u * (0.5 + eyeDx + er * 0.9), u * (eyeY + er * 2.2)), u * 0.06, cheek);
    final ny = u * (eyeY + er * 2.6);
    if (!noNoseMouth) {
      c.drawPath(_ov(Offset(u * 0.5, ny), u * 0.045, u * 0.032), Paint()..color = nose);
      c.drawCircle(Offset(u * 0.488, ny - u * 0.01), u * 0.01, Paint()..color = alpha(Colors.white, 0.7));
    }
    _mouth(c, Offset(u * 0.5, ny + u * 0.07), u * 0.2, u * 0.05, tilt: u * 0.008);
    if (whiskers) {
      final w = Paint()..style = PaintingStyle.stroke..strokeWidth = u * 0.012..strokeCap = StrokeCap.round..color = alpha(Colors.white, 0.8);
      for (final sgn in [-1.0, 1.0]) {
        c.drawLine(Offset(u * (0.5 + sgn * 0.2), ny), Offset(u * (0.5 + sgn * 0.38), ny - u * 0.03), w);
        c.drawLine(Offset(u * (0.5 + sgn * 0.2), ny + u * 0.03), Offset(u * (0.5 + sgn * 0.38), ny + u * 0.05), w);
      }
    }
  }

  @override
  bool shouldRepaint(MascotPainter old) => old.kind != kind;
}

/// الصورة الرمزية: شخصية مرسومة إذا الإيموجي من القائمة، وإلا النص نفسه.
class Avatar extends StatelessWidget {
  const Avatar(this.avatar, {super.key, this.size = 32});
  final String avatar;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kind = kMascots[avatar];
    if (kind == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: Text(avatar.isEmpty ? '🙂' : avatar, style: TextStyle(fontSize: size * 0.8, height: 1))),
      );
    }
    return RepaintBoundary(
      child: SizedBox(width: size, height: size, child: CustomPaint(painter: MascotPainter(kind))),
    );
  }
}

/// صورة اللعبة (assets/games/<id>.webp). إذا الملف ناقص يرجع للرسم بالكود.
class GameArt extends StatelessWidget {
  const GameArt(this.id, {super.key, required this.fallback, this.size, this.radius = 18});
  final String id;
  final CustomPainter Function() fallback;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final img = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/games/$id.webp',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Padding(padding: const EdgeInsets.all(6), child: CustomPaint(painter: fallback())),
      ),
    );
    return size == null ? img : SizedBox(width: size, height: size, child: img);
  }
}
