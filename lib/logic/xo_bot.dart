import 'dart:math' as math;

import 'xo_logic.dart';

/// عقل الكمبيوتر بإكس أو (Dart صافي). قوته تتبع المستوى:
/// سهل يغلط كثير (بس ياخذ الفوز إذا شافه)، متوسط يحسب لگدام وأحياناً يسهى، صعب بحث أعمق.
class XoBot {
  static Map<String, dynamic>? move(XoModel m, int p, math.Random r) {
    if (m.over || m.turn != p) return null;
    final moves = [for (var i = 0; i < m.board.length; i++) if (m.legal(i)) i];
    if (moves.isEmpty) return null;
    final slip = const [0.45, 0.12, 0.05][m.level];
    int pick;
    if (r.nextDouble() < slip) {
      // يسهى: بس إذا عنده فوز حاضر ياخذه
      pick = moves.firstWhere((i) => _winsNow(m, i), orElse: () => moves[r.nextInt(moves.length)]);
    } else {
      pick = _best(m, moves, r);
    }
    return {'m': 'put', 'i': pick};
  }

  static bool _winsNow(XoModel m, int i) {
    final c = _copy(m)..input(m.turn, {'m': 'put', 'i': i});
    return c.over && c.winner == m.turn;
  }

  static XoModel _copy(XoModel m) => XoModel.restore(m.toJson());

  static int _best(XoModel m, List<int> moves, math.Random r) {
    final depth = m.ultimate ? (m.zone < 0 ? 2 : 3) : (m.level == 1 ? 8 : 9);
    var best = moves.first;
    var bestV = -1e9;
    for (final i in moves..shuffle(r)) {
      final c = _copy(m)..input(m.turn, {'m': 'put', 'i': i});
      final v = -_search(c, depth - 1, -1e9, -bestV);
      if (v > bestV) {
        bestV = v;
        best = i;
      }
    }
    return best;
  }

  /// negamax: القيمة من جهة اللي دوره
  static double _search(XoModel m, int depth, double a, double b) {
    if (m.over) return m.winner < 0 ? 0 : -1000.0 - depth; // اللي لعب قبل فاز
    if (depth <= 0) return m.ultimate ? _eval(m, m.turn) - _eval(m, 1 - m.turn) : 0;
    final moves = [for (var i = 0; i < m.board.length; i++) if (m.legal(i)) i];
    if (moves.isEmpty) return 0;
    var v = -1e9;
    for (final i in moves) {
      final c = _copy(m)..input(m.turn, {'m': 'put', 'i': i});
      v = math.max(v, -_search(c, depth - 1, -b, -a));
      a = math.max(a, v);
      if (a >= b) break;
    }
    return v;
  }

  /// تقييم الكبيرة: لوحات مكسوبة (والوسط أثمن) وخطوط مفتوحة
  static double _eval(XoModel m, int p) {
    var s = 0.0;
    for (var z = 0; z < 9; z++) {
      if (m.big[z] == p) s += z == 4 ? 14 : (z.isEven ? 11 : 9);
      if (m.big[z] >= 0) continue;
      for (final l in XoModel.lines) {
        var mine = 0, theirs = 0;
        for (final c in l) {
          final v = m.board[z * 9 + c];
          if (v == p) mine++;
          if (v == 1 - p) theirs++;
        }
        if (theirs == 0) s += mine == 2 ? 2 : mine * 0.3;
      }
    }
    for (final l in XoModel.lines) {
      var mine = 0, theirs = 0;
      for (final z in l) {
        if (m.big[z] == p) mine++;
        if (m.big[z] == 1 - p || m.big[z] == 2) theirs++;
      }
      if (theirs == 0) s += mine == 2 ? 25 : mine * 4;
    }
    return s;
  }
}
