// تخطيط طاولة الدومينو: flutter test tools/domino_board_test.dart
// مباريات كاملة (كلاسيكي وخمسات) بعدة أحجام شاشات: لا قطعتين راكبات ولا شي يطلع برا الطاولة.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamma/games/domino_board.dart';
import 'package:lamma/logic/domino_bot.dart';
import 'package:lamma/logic/domino_logic.dart';

void main() {
  const sizes = [Size(250, 260), Size(300, 420), Size(360, 330), Size(900, 420), Size(1200, 700)];
  for (final fives in [false, true]) {
    test('layout ${fives ? 'fives' : 'classic'}', () {
      final r = math.Random(3);
      var checked = 0;
      for (var g = 0; g < 25; g++) {
        final m = DominoModel(players: g.isEven ? 2 : 4, crazy: false, seed: 40 + g, fives: fives, goal: 200);
        for (var k = 0; k < 4000 && !m.over && m.round < 2; k++) {
          if (m.phase == 'round') {
            for (var p = 0; p < m.players; p++) {
              m.input(p, {'a': 'next'});
            }
          } else {
            final mv = DominoBot.move(m, m.turn, 2, r);
            if (mv != null) m.input(m.turn, mv);
            for (final s in sizes) {
              final (l, cam) = fitBoard(m, s, 34);
              expect(hasOverlap(l), isFalse, reason: 'overlap g=$g k=$k size=$s');
              final b = cam.rectToScreen(l.bounds, s);
              expect(b.left >= -1 && b.top >= -1 && b.right <= s.width + 1 && b.bottom <= s.height + 1, isTrue, reason: 'outside g=$g k=$k size=$s $b');
              expect(l.tiles.length, m.chainLen + m.up.length ~/ 3 + m.dn.length ~/ 3);
              checked++;
            }
          }
          m.advance(0.25);
          m.drainEvents();
        }
      }
      expect(checked, greaterThan(500));
    });
  }
}
