// اختبار عقل الكمبيوتر بأربعة بالصف: كل مستوى ضد لاعب عشوائي.
import 'dart:math' as math;

import '../lib/logic/connect4_bot.dart';
import '../lib/logic/connect4_logic.dart';

void main() {
  final r = math.Random(5);
  var bad = 0;
  for (var lv = 0; lv < 3; lv++) {
    var w = 0, l = 0, d = 0;
    final sw = Stopwatch()..start();
    for (var g = 0; g < 20; g++) {
      final m = Connect4Model(players: 2, crazy: false, seed: g, level: lv);
      for (var k = 0; k < 300 && !m.over; k++) {
        final p = m.turn;
        final mv = p == g % 2 ? Connect4Bot.move(m, p, r) : (Connect4Bot.moves(m, p)..shuffle(r)).first;
        m.input(p, mv!);
      }
      if (m.winner == g % 2) {
        w++;
      } else if (!m.over || m.winner < 0) {
        d++;
      } else {
        l++;
      }
    }
    print('level $lv vs random: win $w draw $d lose $l (${sw.elapsedMilliseconds}ms)');
    if (w < 16) bad++;
  }
  if (bad > 0) throw 'c4 bot weak';
  print('OK');
}
