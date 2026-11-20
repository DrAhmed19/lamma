import 'game_model.dart';

/// قواعد إكس أو
class XoModel extends GameModel {
  XoModel({required super.players, required super.crazy, required super.seed});

  XoModel.restore(super.j)
      : board = [for (final v in j['board'] as List) v as int],
        turn = j['turn'] as int,
        starter = j['starter'] as int,
        winLine = (j['line'] as List?)?.map((e) => e as int).toList(),
        win = j['win'] as int,
        finished = j['fin'] == true,
        wins = [for (final v in j['wins'] as List) v as int],
        super.restore();

  static const lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  @override
  String get id => 'xo';

  List<int> board = List.filled(9, -1);
  int turn = 0;
  int starter = 0;
  List<int>? winLine;
  int win = -1;
  bool finished = false;
  List<int> wins = [0, 0];

  @override
  bool get over => finished;
  @override
  int get winner => win;
  @override
  List<int> get scores => wins;

  @override
  void input(int player, Map<String, dynamic> d) {
    if (d['m'] != 'put') return;
    final i = d['i'];
    if (finished || player != turn || i is! int || i < 0 || i > 8 || board[i] >= 0) return;
    board[i] = turn;
    emit('put', {'i': i, 'p': turn});
    for (final l in lines) {
      if (board[l[0]] == turn && board[l[1]] == turn && board[l[2]] == turn) {
        winLine = l;
        win = turn;
        wins[turn]++;
        finished = true;
        emit('win', {'p': turn});
        return;
      }
    }
    if (!board.contains(-1)) {
      win = -1;
      finished = true;
      emit('draw');
      return;
    }
    turn = 1 - turn;
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
    board = List.filled(9, -1);
    winLine = null;
    win = -1;
    finished = false;
    emit('again');
  }

  @override
  Map<String, dynamic> save() => {
        'board': board,
        'turn': turn,
        'starter': starter,
        'line': winLine,
        'win': win,
        'fin': finished,
        'wins': wins,
      };
}
