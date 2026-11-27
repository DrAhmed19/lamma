// اختبار عقل الكمبيوتر بإكس أو: كل مستوى ضد لاعب عشوائي، والصعب ضد السهل.
import 'dart:math' as math;

import '../lib/logic/xo_bot.dart';
import '../lib/logic/xo_logic.dart';

int game(int level, bool Function(int p) smart, math.Random r) {
  final m = XoModel(players: 2, crazy: false, seed: r.nextInt(1 << 30), level: level);
  for (var k = 0; k < 400 && !m.over; k++) {
    final p = m.turn;
    Map<String, dynamic>? mv;
    if (smart(p)) {
      mv = XoBot.move(m, p, r);
    } else {
      final ok = [for (var i = 0; i < m.board.length; i++) if (m.legal(i)) i];
      mv = {'m': 'put', 'i': ok[r.nextInt(ok.length)]};
    }
    m.input(p, mv!);
  }
  return m.over ? m.winner : -2;
}

void main() {
  final r = math.Random(3);
  var bad = 0;
  for (var lv = 0; lv < 3; lv++) {
    var w = 0, l = 0, d = 0;
    final sw = Stopwatch()..start();
    for (var g = 0; g < 30; g++) {
      final res = game(lv, (p) => p == g % 2, r);
      if (res == g % 2) {
        w++;
      } else if (res == -1 || res == -2) {
        d++;
      } else {
        l++;
      }
    }
    print('level $lv vs random: win $w draw $d lose $l (${sw.elapsedMilliseconds}ms)');
    if (w < (lv == 0 ? 15 : 22)) bad++;
  }
  if (bad > 0) throw 'xo bot weak';
  print('OK');
}
