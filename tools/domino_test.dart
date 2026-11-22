// اختبار قواعد الدومينو (الكلاسيكي والخمسات) والبوت: dart run tools/domino_test.dart
import 'dart:convert';
import 'dart:math' as math;

import '../lib/logic/domino_bot.dart';
import '../lib/logic/domino_logic.dart';

var _bad = 0;
void check(bool ok, String what) {
  print('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) _bad++;
}

int t(int a, int b) => DominoModel.tileOf(a, b);

/// موديل بطاولة جاهزة: نحط القطع بيد اللاعب الأول ونلعبها بالترتيب
DominoModel board(List<(int, int, String)> plays, {bool fives = true}) {
  final m = DominoModel(players: 2, crazy: false, seed: 1, fives: fives);
  m.chain = [];
  m.up = [];
  m.dn = [];
  m.mustStart = -1;
  m.side = [0, 0];
  for (final (a, b, s) in plays) {
    final x = t(a, b);
    m.hands = [
      [x, t(0, 0) == x ? t(0, 1) : t(0, 0)],
      [t(6, 6) == x ? t(5, 6) : t(6, 6)],
    ];
    m.pile = [t(2, 3)]; // حتى ما تتسكّر
    m.turn = 0;
    m.phase = 'play';
    m.input(0, {'a': 'play', 't': x, 's': s});
  }
  return m;
}

void rules() {
  check(t(0, 0) == 0 && t(0, 1) == 1 && t(6, 6) == 27 && t(3, 5) == t(5, 3), 'tileOf');
  var m = board([(5, 5, 'r')]);
  check(m.endsSum == 10 && m.side[0] == 10, '5-5 alone scores 10');
  check(m.spinner && !m.crossOpen && m.arms.length == 2, 'spinner, cross closed');
  m = board([(5, 5, 'r'), (5, 0, 'r')]);
  check(m.endsSum == 10, 'spinner counts full while one side empty (10+0)');
  m = board([(5, 5, 'r'), (5, 0, 'r'), (5, 1, 'l')]);
  check(m.crossOpen && m.arms.length == 4, 'cross opens after both sides');
  check(m.endsSum == 1, 'ends after both sides: 0 + 1');
  check(m.sidesFor(t(5, 4)).contains('u') && m.sidesFor(t(5, 4)).contains('d'), '5-4 fits up/down');
  m = board([(5, 5, 'r'), (5, 0, 'r'), (5, 1, 'l'), (5, 4, 'u')]);
  check(m.endsSum == 5, '0 + 1 + 4 = 5');
  m = board([(4, 4, 'r'), (4, 6, 'r'), (6, 6, 'r')]);
  check(m.endsSum == 8 + 12, 'double at the end counts both halves');
  check(DominoModel.round5(12) == 10 && DominoModel.round5(13) == 15, 'round to 5');
  // الكلاسيكي ما يتفرع ولا ينحسب بنص الجولة
  m = board([(5, 5, 'r'), (5, 0, 'r'), (5, 1, 'l')], fives: false);
  check(!m.spinner && m.arms.length == 2 && m.side[0] == 0, 'classic: no spinner, no mid-round points');
  // الخمسات تبدي بأعلى دبل كل جولة
  m = DominoModel(players: 4, crazy: false, seed: 9, fives: true);
  check(DominoModel.isDouble(m.mustStart), 'fives opens with a double');
  // حفظ واستعادة
  m = board([(5, 5, 'r'), (5, 0, 'r'), (5, 1, 'l'), (5, 4, 'u')]);
  final back = DominoModel.restore(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
  check(back.fives && back.goal == 100 && back.up.length == 3 && back.endsSum == 5, 'save/restore keeps arms');
}

/// مباريات كاملة بوت ضد بوت بكل المستويات والأوضاع
void bots() {
  final r = math.Random(7);
  for (final fives in [false, true]) {
    for (final n in [2, 4]) {
      for (var lv = 0; lv <= 4; lv++) {
        var m = DominoModel(players: n, crazy: false, seed: 100 + lv + n, fives: fives, goal: fives ? 150 : null);
        var ok = true;
        try {
          for (var k = 0; k < 40000 && !m.over; k++) {
            if (m.phase == 'round') {
              for (var p = 0; p < n; p++) {
                m.input(p, {'a': 'next'});
              }
            } else {
              final mv = DominoBot.move(m, m.turn, lv, r);
              if (mv != null) m.input(m.turn, mv);
            }
            m.advance(0.25);
            m.drainEvents();
            if (k % 50 == 0) m = DominoModel.restore(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
          }
        } catch (e) {
          ok = false;
          print('  $e');
        }
        check(ok && m.over && m.scores.any((s) => s >= m.goal), 'bots finish: ${fives ? 'fives' : 'classic'} n=$n level=$lv (${m.scores})');
      }
    }
  }
  // المستوى الأقوى يغلب الأضعف أغلب المرات (بالخمسات)
  var strong = 0;
  const games = 30;
  for (var g = 0; g < games; g++) {
    final m = DominoModel(players: 2, crazy: false, seed: 500 + g, fives: true);
    for (var k = 0; k < 40000 && !m.over; k++) {
      if (m.phase == 'round') {
        m.input(0, {'a': 'next'});
        m.input(1, {'a': 'next'});
      } else {
        final mv = DominoBot.move(m, m.turn, m.turn == 0 ? 4 : 0, r);
        if (mv != null) m.input(m.turn, mv);
      }
      m.advance(0.25);
      m.drainEvents();
    }
    if (m.winner == 0) strong++;
  }
  check(strong >= games * 0.7, 'level 4 beats level 0 ($strong/$games)');
}

void main() {
  rules();
  bots();
  print(_bad == 0 ? 'كلشي تمام' : '$_bad فشل');
  if (_bad > 0) throw Exception('failed');
}
