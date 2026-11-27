// الكمبيوتر بسؤال وجواب: المستويات تخلّص المباراة، والصعب أدق من السهل.
import 'dart:math' as math;

import '../lib/logic/models.dart';
import '../lib/logic/quiz_logic.dart';

void main() {
  final r = math.Random(1);
  final totals = <int>[];
  for (var lv = 0; lv < 3; lv++) {
    var sum = 0;
    for (var g = 0; g < 5; g++) {
      final m = QuizModel(players: 2, crazy: false, seed: g, level: lv);
      for (var t = 0; t < 20 * 300 && !m.over; t++) {
        m.advance(0.05);
        for (var p = 0; p < 2; p++) {
          final mv = botMove(m, p, lv, r);
          if (mv != null) m.input(p, mv);
        }
      }
      if (!m.over) throw 'quiz lv$lv did not finish';
      sum += m.score[0] + m.score[1];
    }
    totals.add(sum);
    print('level $lv total points $sum');
  }
  if (totals[0] >= totals[1]) throw 'level 0 should score less than level 1';
  print('OK');
}
