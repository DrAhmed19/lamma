import 'dart:math' as math;

import 'pigeon_logic.dart';

/// عقل الكمبيوتر بالحمامة: يختار حمامة (مو غراب) ويصوّب مع تقدير حركتها.
/// الضعيف يصوّب بخطأ كبير وبطيء، والقوي دقيق وسريع.
class PigeonBot {
  static double _dist(double a, double b, double c, double d) => math.sqrt((a - c) * (a - c) + (b - d) * (b - d));

  static PBird? _target(PigeonModel m, int p) {
    final a = m.anchor(p);
    PBird? best;
    var bestV = -1e9;
    for (final b in m.birds) {
      if (b.hit || b.kind == kCrow) continue;
      // قريبة وذهبية أحسن، والمرمى لازم صوب الخصم
      final d = _dist(a.$1, a.$2, b.x, b.y);
      if (d > m.worldH * 1.2) continue;
      final v = (b.kind == kGold ? 120.0 : 0.0) - d + (b.small ? -40 : 0);
      if (v > bestV) {
        bestV = v;
        best = b;
      }
    }
    return best;
  }

  /// null = ماكو شي يصوّبه هسة. الحركة تحمل 'w' (وقت الانتظار بالملّي ثانية).
  static Map<String, dynamic>? move(PigeonModel m, int p, int level, math.Random r, {bool peek = false}) {
    if (!m.started || m.over || m.out[p] || m.time < m.readyAt[p] || m.frozen(p)) return null;
    final lv = level.clamp(0, 2);
    final b = _target(m, p);
    if (b == null) return null;
    final w = (const [900, 550, 300][lv] + r.nextInt(300));
    if (peek) return {'w': w};
    final a = m.anchor(p);
    final h = m.worldH;
    // قوة تكفي للمسافة، ونحسب وقت الوصول ونتقدّم أمام الحمامة
    var tx = b.x, ty = b.y;
    var pw = 1.0;
    for (var i = 0; i < 3; i++) {
      final d = _dist(a.$1, a.$2, tx, ty);
      pw = (((d * 1.12) / h - 0.5) / 0.75).clamp(0.45, 1.0);
      final speed = h * (0.6 + 0.9 * pw);
      final t = d / speed;
      final lead = const [0.35, 0.8, 1.0][lv];
      tx = b.x + b.vx * t * lead;
      ty = b.y + b.vy * t * lead;
    }
    var dx = tx - a.$1, dy = ty - a.$2;
    final fy = m.isTop(p) ? 1.0 : -1.0;
    if (dy * fy < 8) dy = 8 * fy;
    // خطأ بالتصويب
    final err = (r.nextDouble() - 0.5) * 2 * const [0.14, 0.06, 0.016][lv];
    final ang = math.atan2(dy, dx) + err;
    final len = math.sqrt(dx * dx + dy * dy);
    return {'m': 'shot', 'dx': math.cos(ang) * len, 'dy': math.sin(ang) * len, 'pw': pw, 'w': w};
  }
}
