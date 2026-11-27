import 'dart:math' as math;

import 'muhaibes_logic.dart';

/// عقل الكمبيوتر بالمحيبس (للغرف). ما يشوف مكان المحبس إذا كان بالفريق الحازر:
/// المخبّي يخبّي عشوائي، والقائد يفتح قبضات ويقرر "بات" حسب المستوى.
class MuhaibesBot {
  static Map<String, dynamic>? move(MuhaibesModel m, int p, int level, math.Random r) {
    if (m.over || m.out[p]) return null;
    final lv = level.clamp(0, 2);
    if (m.phase == 'hide' && p == m.hider) {
      final mine = [
        for (final f in m.closedFists) f,
      ];
      if (mine.isEmpty) return null;
      return {'a': 'hide', 'f': mine[r.nextInt(mine.length)], 'w': 1500 + r.nextInt(2500)};
    }
    if (m.phase == 'guess' && p == m.leader) {
      final closed = m.closedFists;
      if (closed.isEmpty) return null;
      // كل ما قلّت القبضات المغلقة زاد احتمال "بات": السهل يتسرع، والصعب يصبر لحد الاثنين
      final bat = closed.length <= const [4, 3, 2][lv] && (closed.length <= 2 || r.nextDouble() < 0.45);
      final f = closed[r.nextInt(closed.length)];
      return {'a': bat ? 'bat' : 'open', 'f': f, 'w': 2000 + r.nextInt(2500)};
    }
    return null;
  }
}
