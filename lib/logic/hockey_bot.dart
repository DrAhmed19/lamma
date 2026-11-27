import 'dart:math' as math;

import 'hockey_logic.dart';

/// عقل الكمبيوتر بالهوكي: يدز مكان المضرب كل تكّة مثل اللاعب. يدافع قدام المرمى،
/// ولمّن القرص بنصفه يضرب بإتجاه مرمى الخصم. الضعيف بطيء ويخطي بالتصويب.
class HockeyBot {
  static Map<String, dynamic>? move(HockeyModel m, int p, int level, math.Random r) {
    if (m.over || m.counting) return null;
    final lv = level.clamp(0, 2);
    const h = HockeyModel.h;
    final ownY = p == 0 ? h : 0.0, oppY = p == 0 ? 0.0 : h;
    final sgn = p == 0 ? 1.0 : -1.0; // + = صوب مرماه
    final ux = m.puckX, uy = m.puckY;
    // القرص بنصفي؟ (المسافة من خط الوسط صوبي)
    final mine = (uy - h / 2) * sgn > -0.03;
    final sp = math.sqrt(m.puckVx * m.puckVx + m.puckVy * m.puckVy);
    // خطأ ثابت لكل نص ثانية (مو يهتز كل إطار)
    final seed = (m.time * 2).floor() + p * 31;
    final noise = (((seed * 7919) % 1000) / 1000 - 0.5) * const [0.30, 0.15, 0.04][lv];
    var tx = 0.5, ty = ownY - sgn * h * 0.14;
    final cornered = mine && sp < 0.4 && (uy - ownY).abs() <= 0.2;
    final canAttack = mine && sp < const [1.8, 3.0, 9.0][lv] && !cornered;
    if (cornered) {
      // القرص لازگ بنهاية ساحتي: أوقف جنبه (جهة الوسط) وأخطف بالمضرب لفوگ
      final dx = ux < 0.5 ? 1.0 : -1.0;
      final sx = ux + dx * 0.17, sy = uy - sgn * 0.02;
      final d = math.sqrt(math.pow(m.padX[p] - sx, 2) + math.pow(m.padY[p] - sy, 2));
      if (d > 0.07 && (m.padX[p] - ux) * dx < 0.1) {
        tx = sx;
        ty = sy;
      } else {
        tx = ux - dx * 0.03;
        ty = uy - sgn * 0.3;
      }
    } else if (canAttack) {
      // نقطة وراء القرص على خط مرمى الخصم، وإذا قريب منها نضرب
      var vx = ux - 0.5, vy = uy - oppY;
      final len = math.sqrt(vx * vx + vy * vy);
      vx /= len;
      vy /= len;
      final bx = ux + vx * 0.13, by = uy + vy * 0.13;
      final d = math.sqrt(math.pow(m.padX[p] - bx, 2) + math.pow(m.padY[p] - by, 2));
      if (d > 0.1) {
        tx = bx;
        ty = by;
      } else {
        tx = ux - vx * 0.12 + noise;
        ty = uy - vy * 0.12;
      }
    } else {
      // دفاع: يتابع القرص بالعرض قدام المرمى
      final follow = const [0.55, 0.8, 1.0][lv];
      tx = 0.5 + (ux - 0.5) * follow + noise;
      // إذا القرص يجي صوبي بسرعة، يتقدم شوية
      ty = ownY - sgn * h * (m.puckVy * sgn > 0.6 ? 0.1 : 0.15);
    }
    // الضعيف أبطأ: يتحرك جزء من المسافة
    final k = const [0.55, 0.8, 1.0][lv];
    tx = m.padX[p] + (tx - m.padX[p]) * k;
    ty = m.padY[p] + (ty - m.padY[p]) * k;
    return {'m': 'pad', 'x': m.cx(tx), 'y': m.cy(p, ty), 'w': 0};
  }
}
