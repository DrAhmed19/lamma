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
  // الشفافية تتغير كل إطار (كتابة تختفي تدريجياً)، فنقرّبها لـ 12 درجة،
  // وإلا كل إطار يصير نص جديد ونعيد قياسه = تقطيع (خصوصاً بالآيفون لمّن تنصاد حمامة)
  color = _q(color);
  if (shadows != null) shadows = [for (final s in shadows) Shadow(color: _q(s.color), blurRadius: s.blurRadius, offset: s.offset)];
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

Color _q(Color c) => c.withValues(alpha: (c.a * 12).round() / 12);

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

/// «عالم» اللعبة: خلفية بلون أيقونتها (فاتحة من فوق) ويا دوائر ناعمة، حسب النموذج الجديد.
void paintWorld(Canvas canvas, Rect r, Color col) {
  canvas.drawRect(
    r,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [lighten(col, 0.2), col, darken(col, 0.12)],
        stops: const [0, 0.55, 1],
      ).createShader(r),
  );
  final p = Paint()..color = alpha(Colors.white, 0.08);
  final m = r.shortestSide;
  canvas.drawCircle(Offset(r.left + r.width * 0.88, r.top + r.height * 0.06), m * 0.38, p);
  canvas.drawCircle(Offset(r.left + r.width * 0.06, r.top + r.height * 0.52), m * 0.26, p);
  canvas.drawCircle(Offset(r.left + r.width * 0.78, r.top + r.height * 0.95), m * 0.32, p);
}

/// ألوان عوالم الألعاب (نفس خلفية أيقونة كل لعبة)
const kWorld = {
  'xo': Color(0xFF5A6CF0),
  'connect4': Color(0xFFF2545B),
  'hockey': Color(0xFF3B8CF5),
  'reaction': Color(0xFF2EB872),
  'tug': Color(0xFFD9954E),
  'quiz': Color(0xFF9B5DE5),
  'whois': Color(0xFFFF9A3D),
  'spy': Color(0xFFE5583D),
  'muhaibes': Color(0xFFEC4D93),
};
