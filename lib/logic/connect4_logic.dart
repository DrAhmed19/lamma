import 'dart:math' as math;

import 'game_model.dart';

/// قواعد أربعة بالصف. اللاعب 0 أحمر، 1 أصفر.
/// [level]: 0 سهل (العادية)، 1 متوسط (قنبلة وحدة لكل لاعب: تمسح اللي حواليها)،
/// 2 صعب («اسحب من تحت»: تگدر تطلع قطعتك من أسفل العمود فتنزل الباقي).
class Connect4Model extends GameModel {
  Connect4Model({required super.players, required super.crazy, required super.seed, int level = 0}) : level = level.clamp(0, 2);

  Connect4Model.restore(super.j)
      : grid = [
          for (final r in j['grid'] as List) [for (final v in r as List) v as int]
        ],
        turn = j['turn'] as int,
        starter = j['starter'] as int,
        winCells = (j['cells'] as List?)?.map((e) => e as int).toList(),
        win = j['win'] as int,
        finished = j['fin'] == true,
        wins = [for (final v in j['wins'] as List) v as int],
        level = (j['lv'] as int?) ?? 0,
        bombs = [for (final v in (j['bombs'] as List?) ?? const [1, 1]) v as int],
        super.restore();

  static const cols = 7, rows = 6;

  @override
  String get id => 'connect4';

  List<List<int>> grid = List.generate(rows, (_) => List.filled(cols, -1));
  int turn = 0;
  int starter = 0;

  /// خلايا الفوز: كل خلية = row * cols + col
  List<int>? winCells;
  int win = -1;
  bool finished = false;
  List<int> wins = [0, 0];
  final int level;

  /// قنابل كل لاعب (المتوسط)
  List<int> bombs = [1, 1];

  @override
  bool get over => finished;
  @override
  int get winner => win;
  @override
  List<int> get scores => wins;

  /// أول صف فاضي بالعمود (-1 = مليان)
  int freeRow(int c) {
    for (var r = rows - 1; r >= 0; r--) {
      if (grid[r][c] < 0) return r;
    }
    return -1;
  }

  /// عنده قنبلة ويگدر يستعملها؟
  bool canBomb(int p) => level == 1 && bombs[p] > 0;

  /// عنده قطعة بأسفل العمود [c] يگدر يسحبها؟
  bool canPop(int p, int c) => level == 2 && c >= 0 && c < cols && grid[rows - 1][c] == p;

  @override
  void input(int player, Map<String, dynamic> d) {
    final c = d['c'];
    if (finished || player != turn || c is! int || c < 0 || c >= cols) return;
    if (d['m'] == 'pop') {
      if (!canPop(player, c)) return;
      for (var r = rows - 1; r > 0; r--) {
        grid[r][c] = grid[r - 1][c];
      }
      grid[0][c] = -1;
      emit('pop', {'c': c, 'p': turn});
      return _after();
    }
    if (d['m'] != 'drop') return;
    final r = freeRow(c);
    if (r < 0) return;
    if (d['b'] == true) {
      if (!canBomb(player)) return;
      bombs[player]--;
      // القنبلة تنزل وتنفجر: تمسح الخلايا اللي حواليها (وهي نفسها)، والباقي ينزل
      emit('drop', {'c': c, 'r': r, 'p': turn, 'bomb': true});
      for (var rr = r - 1; rr <= r + 1; rr++) {
        for (var cc = c - 1; cc <= c + 1; cc++) {
          if (rr >= 0 && rr < rows && cc >= 0 && cc < cols) grid[rr][cc] = -1;
        }
      }
      for (var cc = math.max(0, c - 1); cc <= math.min(cols - 1, c + 1); cc++) {
        _gravity(cc);
      }
      emit('boom', {'c': c, 'r': r});
      return _after();
    }
    grid[r][c] = turn;
    emit('drop', {'c': c, 'r': r, 'p': turn});
    _after();
  }

  void _gravity(int c) {
    final col = [for (var r = rows - 1; r >= 0; r--) if (grid[r][c] >= 0) grid[r][c]];
    for (var r = rows - 1, k = 0; r >= 0; r--, k++) {
      grid[r][c] = k < col.length ? col[k] : -1;
    }
  }

  /// بعد أي حركة: فوز اللي لعب، وإلا فوز الخصم (ممكن بالقنبلة أو السحب)، وإلا تعادل
  void _after() {
    for (final p in [turn, 1 - turn]) {
      final w = scan(p);
      if (w != null) {
        winCells = w;
        win = p;
        wins[p]++;
        finished = true;
        emit('win', {'p': p});
        return;
      }
    }
    if (grid[0].every((v) => v >= 0)) {
      win = -1;
      finished = true;
      emit('draw');
      return;
    }
    turn = 1 - turn;
  }

  /// أي أربعة متتالية للاعب [p] بكل اللوحة
  List<int>? scan(int p) {
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (grid[r][c] != p) continue;
        for (final d in dirs) {
          final cells = <int>[];
          var rr = r, cc = c;
          while (rr >= 0 && rr < rows && cc >= 0 && cc < cols && grid[rr][cc] == p) {
            cells.add(rr * cols + cc);
            rr += d.$1;
            cc += d.$2;
          }
          if (cells.length >= 4) return cells;
        }
      }
    }
    return null;
  }

  @override
  void forfeit(int player) {
    if (finished) return;
    win = 1 - player;
    wins[win]++;
    finished = true;
    emit('win', {'p': win, 'forfeit': true});
  }

  @override
  void again() {
    if (!finished) return;
    starter = 1 - starter;
    turn = starter;
    grid = List.generate(rows, (_) => List.filled(cols, -1));
    bombs = [1, 1];
    winCells = null;
    win = -1;
    finished = false;
    emit('again');
  }

  @override
  Map<String, dynamic> save() => {
        'grid': grid,
        'turn': turn,
        'starter': starter,
        'cells': winCells,
        'win': win,
        'fin': finished,
        'wins': wins,
        'lv': level,
        'bombs': bombs,
      };
}
