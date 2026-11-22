import 'dart:math' as math;

import 'domino_logic.dart';

/// بوت الدومينو (Dart صافي). يشوف قطعه والطاولة بس، مثل اللاعب، وما يبص على قطع غيره.
///
/// المستويات: 0 سهل (عشوائي)، 1 عادي (يتخلص من الثقيل)، 2 متوسط (+ نقاط الخمسات)،
/// 3 صعب (+ ما يفتح نقاط للخصم، ويحافظ على قطع تنفعه)، 4 وحش (نفسه بأوزان أقوى وبدون غلط).
class DominoBot {
  static const names = ['سهل', 'عادي', 'متوسط', 'صعب', 'وحش'];

  /// الحركة: {'a':'play','t','s'} أو {'a':'draw'}، أو null = ينتظر (المرور يصير وحده).
  static Map<String, dynamic>? move(DominoModel m, int p, int level, math.Random r) {
    if (m.phase != 'play' || m.turn != p || m.over) return null;
    final moves = <(int, String)>[
      for (final t in m.hands[p])
        for (final s in m.sidesFor(t)) (t, s),
    ];
    if (moves.isEmpty) return m.pile.isNotEmpty ? {'a': 'draw'} : null;
    final lv = level.clamp(0, 4);
    // الضعاف يغلطون أحياناً
    final slip = const [1.0, 0.25, 0.12, 0.04, 0.0][lv];
    if (r.nextDouble() < slip) {
      final mv = moves[r.nextInt(moves.length)];
      return {'a': 'play', 't': mv.$1, 's': mv.$2};
    }
    final unseen = _unseen(m, p);
    final oppCount = _oppHandCount(m, p);
    (int, String)? best;
    var bestV = -1e18;
    for (final mv in moves) {
      var v = _value(m, p, mv.$1, mv.$2, lv, unseen, oppCount);
      v += r.nextDouble() * 0.01; // كسر التعادل
      if (v > bestV) {
        bestV = v;
        best = mv;
      }
    }
    return {'a': 'play', 't': best!.$1, 's': best.$2};
  }

  /// القطع اللي ما يعرف وينها (بيد الخصوم أو بالمخزن)
  static List<int> _unseen(DominoModel m, int p) {
    final seen = <int>{
      ...m.hands[p],
      for (var i = 0; i < m.chain.length; i += 3) m.chain[i],
      for (var i = 0; i < m.up.length; i += 3) m.up[i],
      for (var i = 0; i < m.dn.length; i += 3) m.dn[i],
    };
    return [for (var t = 0; t < 28; t++) if (!seen.contains(t)) t];
  }

  /// عدد قطع اللاعب الجاي (الخصم)
  static int _oppHandCount(DominoModel m, int p) => m.hands[(p + 1) % m.players].length;

  static double _value(DominoModel m, int p, int t, String s, int lv, List<int> unseen, int oppCount) {
    final pip = DominoModel.pips(t).toDouble();
    if (lv == 1) return pip;
    final gain = m.scoreIfPlayed(t, s).toDouble();
    var v = gain * 10 + pip;
    if (lv < 3) return v;
    // نجرب الحركة على نسخة
    final c = DominoModel.restore(m.toJson());
    c.input(p, {'a': 'play', 't': t, 's': s});
    if (c.phase != 'play') return v + 1000; // خلّص أو وصل الهدف
    // خطر: أعلى نقاط يقدر الخصم يجيبها بالرد، مضروبة باحتمال إنه عنده القطعة
    final hold = unseen.isEmpty ? 0.0 : math.min(1.0, oppCount / unseen.length);
    var danger = 0.0;
    for (final u in unseen) {
      for (final a in c.sidesFor(u)) {
        final g = c.scoreIfPlayed(u, a).toDouble();
        if (g * hold > danger) danger = g * hold;
      }
    }
    // مرونة: كم قطعة من قطعي تبقى تنلعب بعد الحركة
    final mine = [for (final x in m.hands[p]) if (x != t) x];
    var flex = 0;
    for (final x in mine) {
      if (c.sidesFor(x).isNotEmpty) flex++;
    }
    // الدبلات صعبة تنلعب: الأحسن نتخلص منها بدري
    final dbl = DominoModel.isDouble(t) ? 1.0 : 0.0;
    final w = lv == 4 ? 1.6 : 1.0;
    v += -danger * 6 * w + flex * 3 * w + dbl * 4 * w;
    // بالكلاسيكي: إذا الخصم قطعه قليلة، نتخلص من الثقيل أسرع
    if (!m.fives && oppCount <= 2) v += pip * 2;
    return v;
  }
}
