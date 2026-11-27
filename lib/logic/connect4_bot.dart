import 'dart:math' as math;

import 'connect4_logic.dart';

/// عقل الكمبيوتر بأربعة بالصف (Dart صافي): negamax بعمق حسب المستوى.
class Connect4Bot {
  static List<Map<String, dynamic>> moves(Connect4Model m, int p) {
    final o = <Map<String, dynamic>>[];
    for (var c = 0; c < Connect4Model.cols; c++) {
      if (m.freeRow(c) >= 0) {
        o.add({'m': 'drop', 'c': c});
        if (m.canBomb(p)) o.add({'m': 'drop', 'c': c, 'b': true});
      }
      if (m.canPop(p, c)) o.add({'m': 'pop', 'c': c});
    }
    return o;
  }

  static Connect4Model _copy(Connect4Model m) => Connect4Model.restore(m.toJson());

  static Map<String, dynamic>? move(Connect4Model m, int p, math.Random r) {
    if (m.over || m.turn != p) return null;
    final all = moves(m, p);
    if (all.isEmpty) return null;
    final slip = const [0.4, 0.12, 0.05][m.level];
    all.shuffle(r);
    // فوز حاضر دائماً ياخذه
    for (final mv in all) {
      final c = _copy(m)..input(p, mv);
      if (c.over && c.winner == p) return mv;
    }
    if (r.nextDouble() < slip) {
      // يسهى، بس ما يترك الخصم يفوز بحركة وحدة إذا يگدر يمنعه
      final safe = [
        for (final mv in all)
          if (!_oppWins(_copy(m)..input(p, mv), 1 - p)) mv
      ];
      final pool = safe.isEmpty ? all : safe;
      return pool[r.nextInt(pool.length)];
    }
    final depth = m.level == 0 ? 5 : 3;
    var best = all.first;
    var bestV = -1e9;
    for (final mv in all) {
      final c = _copy(m)..input(p, mv);
      final v = -_search(c, depth - 1, -1e9, 1e9) + _centre(mv) * 0.01;
      if (v > bestV) {
        bestV = v;
        best = mv;
      }
    }
    return best;
  }

  static double _centre(Map<String, dynamic> mv) => 3 - ((mv['c'] as int) - 3).abs().toDouble();

  static bool _oppWins(Connect4Model c, int opp) {
    if (c.over) return c.winner == opp;
    for (final mv in moves(c, opp)) {
      final d = _copy(c)..input(opp, mv);
      if (d.over && d.winner == opp) return true;
    }
    return false;
  }

  /// القيمة من جهة اللي دوره
  static double _search(Connect4Model m, int depth, double a, double b) {
    if (m.over) return m.winner < 0 ? 0 : -1000.0 - depth;
    if (depth <= 0) return _eval(m, m.turn) - _eval(m, 1 - m.turn);
    var v = -1e9;
    for (final mv in moves(m, m.turn)) {
      final c = _copy(m)..input(m.turn, mv);
      v = math.max(v, -_search(c, depth - 1, -b, -a));
      a = math.max(a, v);
      if (a >= b) break;
    }
    return v;
  }

  /// نوافذ من 4 بيها قطعي بدون قطع الخصم: كل ما أكثر قطع أحسن
  static double _eval(Connect4Model m, int p) {
    var s = 0.0;
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (var r = 0; r < Connect4Model.rows; r++) {
      for (var c = 0; c < Connect4Model.cols; c++) {
        for (final d in dirs) {
          var mine = 0, theirs = 0, ok = true;
          for (var k = 0; k < 4; k++) {
            final rr = r + d.$1 * k, cc = c + d.$2 * k;
            if (rr < 0 || rr >= Connect4Model.rows || cc < 0 || cc >= Connect4Model.cols) {
              ok = false;
              break;
            }
            final v = m.grid[rr][cc];
            if (v == p) mine++;
            if (v == 1 - p) theirs++;
          }
          if (ok && theirs == 0) s += mine == 3 ? 5 : (mine == 2 ? 1.5 : (mine == 1 ? 0.2 : 0));
        }
      }
      if (m.grid[r][3] == p) s += 0.6;
    }
    return s;
  }
}
