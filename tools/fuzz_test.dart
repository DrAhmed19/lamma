// اختبار ضغط لكل الألعاب: dart run tools/fuzz_test.dart
// كل لعبة، بكل أعداد اللاعبين المسموحة وبالوضعين: حركات عشوائية (صحيحة وغلط)، طلوع ورجوع لاعبين،
// "مرة ثانية"، وحفظ/استعادة (مثل السيرفر) ونسخة كل لاعب (viewFor). أي استثناء أو حالة ما ترجع = فشل.
import 'dart:convert';
import 'dart:math' as math;

import '../lib/logic/game_model.dart';
import '../lib/logic/models.dart';
import '../lib/net/lan_room.dart' show gameFits, gameMax, gameMin;

var _bad = 0;

Map<String, dynamic> randomInput(String id, GameModel m, math.Random r, int p) {
  final junk = r.nextInt(12) == 0;
  if (junk) {
    // حركات غلط: لازم اللعبة تتجاهلها بدون ما تنكسر
    return [
      <String, dynamic>{},
      {'m': 'x', 'a': 'y'},
      {'m': 'put', 'i': 99},
      {'m': 'drop', 'c': -1},
      {'a': 'vote', 't': 'z'},
      {'m': 'shot', 'dx': double.nan, 'dy': 1, 'pw': 1},
      {'m': 'pad', 'x': double.infinity, 'y': 0},
      {'a': 'play', 't': 999, 's': 'q'},
      {'a': 'bat', 'f': -5},
    ][r.nextInt(9)];
  }
  switch (id) {
    case 'xo':
      return {'m': 'put', 'i': r.nextInt(9)};
    case 'connect4':
      return {'m': 'drop', 'c': r.nextInt(7)};
    case 'tug':
    case 'reaction':
      return {'m': 'tap'};
    case 'hockey':
      return r.nextBool() ? {'m': 'pad', 'x': r.nextDouble() * 1.2 - 0.1, 'y': r.nextDouble() * 1.2 - 0.1} : {'m': 'rel'};
    case 'pigeon':
      return {'m': 'shot', 'dx': r.nextDouble() * 2 - 1, 'dy': r.nextDouble() * 2 - 1, 'pw': r.nextDouble()};
    case 'quiz':
      return {'m': 'ans', 'a': r.nextInt(4)};
    case 'muhaibes':
      return {'a': ['hide', 'aim', 'open', 'bat', 'shake'][r.nextInt(5)], 'f': r.nextInt(m.players * 2)};
    case 'domino':
      final j = m.toJson();
      final hands = j['hands'] as List;
      final hand = p < hands.length ? hands[p] as List : const [];
      if (hand.isEmpty || r.nextInt(5) == 0) return {'a': 'draw'};
      return {'a': 'play', 't': hand[r.nextInt(hand.length)], 's': r.nextBool() ? 'l' : 'r'};
    case 'whois':
      return {'a': 'vote', 't': r.nextInt(m.players)};
    case 'spy':
      return {'a': ['ask', 'ask', 'ask', 'call', 'vote', 'vote', 'guess'][r.nextInt(7)], 't': r.nextInt(m.players * 2)};
  }
  return {};
}

void run(String id, int n, bool crazy, int seed) {
  final r = math.Random(seed);
  var m = createModel(id, players: n, crazy: crazy, seed: seed);
  final hz = m.tickHz > 0 ? m.tickHz : 10;
  final dt = 1 / hz;
  var overs = 0;
  final where = '$id n=$n crazy=$crazy seed=$seed';
  try {
    for (var t = 0; t < hz * 240; t++) {
      // حركات
      for (var k = 0; k < 1 + r.nextInt(3); k++) {
        final p = r.nextInt(n);
        m.input(p, randomInput(id, m, r, p));
      }
      // انقطاع ورجوع، وطلوع نهائي نادر
      if (r.nextInt(400) == 0) m.connection(r.nextInt(n), r.nextBool());
      if (r.nextInt(3000) == 0) m.forfeit(r.nextInt(n));
      m.advance(dt);
      m.drainEvents();
      // مثل السيرفر: حفظ واستعادة، ونسخة كل لاعب
      if (t % 97 == 0) {
        final j = jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
        m = restoreModel(j);
        for (var p = -1; p < n; p++) {
          restoreModel(jsonDecode(jsonEncode(m.viewFor(p))) as Map<String, dynamic>);
        }
        m.scores;
        m.winners;
      }
      if (m.over) {
        overs++;
        if (overs > 5) break;
        m.again();
      }
    }
  } catch (e, st) {
    _bad++;
    print('FAIL $where: $e\n${st.toString().split('\n').take(6).join('\n')}');
  }
}

void main() {
  var runs = 0;
  for (final id in onlineGames) {
    final maxN = gameMax[id] ?? 2;
    for (var n = gameMin[id] ?? 2; n <= maxN; n++) {
      if (!gameFits(id, n)) continue;
      for (final crazy in [false, true]) {
        for (var seed = 1; seed <= 3; seed++) {
          run(id, n, crazy, seed * 7919 + n);
          runs++;
        }
      }
    }
  }
  print(_bad == 0 ? 'كلشي تمام ($runs تجربة)' : '$_bad فشل من $runs');
  if (_bad > 0) throw Exception('failed');
}
