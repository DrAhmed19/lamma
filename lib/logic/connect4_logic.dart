import 'game_model.dart';

/// قواعد أربعة بالصف. اللاعب 0 أحمر، 1 أصفر.
class Connect4Model extends GameModel {
  Connect4Model({required super.players, required super.crazy, required super.seed});

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

  @override
  void input(int player, Map<String, dynamic> d) {
    if (d['m'] != 'drop') return;
    final c = d['c'];
    if (finished || player != turn || c is! int || c < 0 || c >= cols) return;
    final r = freeRow(c);
    if (r < 0) return;
    grid[r][c] = turn;
    emit('drop', {'c': c, 'r': r, 'p': turn});
    final w = _checkWin(r, c, turn);
    if (w != null) {
      winCells = w;
      win = turn;
      wins[turn]++;
      finished = true;
      emit('win', {'p': turn});
      return;
    }
    if (grid[0].every((v) => v >= 0)) {
      win = -1;
      finished = true;
      emit('draw');
      return;
    }
    turn = 1 - turn;
  }

  List<int>? _checkWin(int r, int c, int p) {
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (final d in dirs) {
      final cells = <int>[r * cols + c];
      for (final sgn in [1, -1]) {
        var rr = r + d.$1 * sgn, cc = c + d.$2 * sgn;
        while (rr >= 0 && rr < rows && cc >= 0 && cc < cols && grid[rr][cc] == p) {
          cells.add(rr * cols + cc);
          rr += d.$1 * sgn;
          cc += d.$2 * sgn;
        }
      }
      if (cells.length >= 4) return cells;
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
      };
}
