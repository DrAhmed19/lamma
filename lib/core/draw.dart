import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// يرسم نص بمركز محدد، ويقلبه 180 درجة للاعب المقابل.
void paintText(
  Canvas canvas,
  String text,
  Offset center, {
  double size = 24,
  Color color = Colors.white,
  String family = kDisplay,
  FontWeight weight = FontWeight.w400,
  bool flip = false,
  double maxWidth = 1000,
  List<Shadow>? shadows,
}) {
  // نحفظ النص المجهّز حتى ما نعيد قياسه كل إطار (القياس غالي)
  final key = '$text|$size|${color.toARGB32()}|$family|${weight.value}|$maxWidth|${shadows?.length ?? 0}|${shadows?.firstOrNull?.color.toARGB32()}';
  var tp = _textCache[key];
  if (tp == null) {
    if (_textCache.length > 240) _textCache.clear();
    tp = _textCache[key] = _layoutText(text, size, color, family, weight, maxWidth, shadows);
  }
  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (flip) canvas.rotate(math.pi);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

final _textCache = <String, TextPainter>{};

TextPainter _layoutText(String text, double size, Color color, String family, FontWeight weight, double maxWidth,
    List<Shadow>? shadows) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: family,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: 1.1,
        shadows: shadows,
      ),
    ),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
  )..layout(maxWidth: maxWidth);
}

/// كرة/قرص لامع بلون اللاعب.
/// توهج ناعم بدون MaskFilter.blur (الـ blur كل إطار يثقّل خصوصاً على الآيفون):
/// حلقات شفافة متداخلة تعطي نفس الشكل تقريباً وأخف بكثير.
void softGlow(Canvas canvas, Offset c, double r, Color color, double spread) {
  const steps = 4;
  for (var i = steps; i >= 1; i--) {
    final f = i / steps;
    canvas.drawCircle(c, r + spread * f, Paint()..color = color.withValues(alpha: color.a * 0.32));
  }
}

void paintDisc(Canvas canvas, Offset c, double r, Color color,
    {double glow = 0}) {
  if (glow > 0) {
    softGlow(canvas, c, r, alpha(color, 0.45 * glow * 1.6), r * 0.45);
  }
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 1.0,
        colors: [lighten(color, 0.35), color, darken(color, 0.35)],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect),
  );
  canvas.drawCircle(
    c,
    r * 0.72,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08
      ..color = alpha(darken(color, 0.3), 0.6),
  );
  canvas.drawCircle(
    c.translate(-r * 0.3, -r * 0.35),
    r * 0.18,
    Paint()..color = alpha(Colors.white, 0.35),
  );
}

/// خط متقطع
void dashedLine(Canvas canvas, Offset a, Offset b, Paint p,
    {double dash = 12, double gap = 10}) {
  final d = b - a;
  final len = d.distance;
  if (len == 0) return;
  final dir = d / len;
  var t = 0.0;
  while (t < len) {
    final e = math.min(t + dash, len);
    canvas.drawLine(a + dir * t, a + dir * e, p);
    t = e + gap;
  }
}

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double easeOutBack(double t) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final x = t - 1;
  return 1 + c3 * x * x * x + c1 * x * x;
}

double easeOutCubic(double t) {
  final x = 1 - t;
  return 1 - x * x * x;
}
