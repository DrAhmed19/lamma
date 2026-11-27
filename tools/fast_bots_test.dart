// الكمبيوتر بأسرع إصبع وشد الحبل: يخلّص المباراة، والأقوى يغلب الأضعف.
import 'dart:math' as math;

import '../lib/logic/models.dart';

/// [a] مستوى اللاعب 0 و[b] مستوى اللاعب 1. نرجّع فوز اللاعب 0 (1) أو 1 (0)
int play(String id, int a, int b, int seed) {
  final r = math.Random(seed);
  final m = createModel(id, players: 2, crazy: false, seed: seed, level: a);
  final hz = m.tickHz;
  for (var t = 0; t < hz * 900 && !m.over; t++) {
    m.advance(1 / hz);
    for (var p = 0; p < 2; p++) {
      final mv = botMove(m, p, p == 0 ? a : b, r);
      if (mv != null) m.input(p, mv);
    }
  }
  if (!m.over) throw '$id $a vs $b did not finish';
  return m.winner == 0 ? 1 : 0;
}

void main() {
  for (final id in ['reaction', 'tug', 'hockey']) {
    var strong = 0;
    for (var g = 0; g < 10; g++) {
      // نفس موديل (مستوى اللاعب 0) بس سرعة اللاعب 1 أضعف
      strong += play(id, 2, 0, g + 1);
    }
    print('$id: level2 beat level0 in $strong/10');
    if (strong < 7) throw '$id bot not stronger';
  }
  print('OK');
}
