import 'game_model.dart';

/// قواعد إكس أو. [level]: 0 سهل (العادية)، 1 متوسط (3 قطع لكل لاعب والأقدم تختفي)،
/// 2 صعب (إكس أو الكبيرة: 9 لوحات صغيرة، ومكان حركتك يحدد لوحة خصمك).
class XoModel extends GameModel {
  XoModel({required super.players, required super.crazy, required super.seed, int level = 0})
      : level = level.clamp(0, 2),
        board = List.filled(level == 2 ? 81 : 9, -1);

  XoModel.restore(super.j)
      : board = [for (final v in j['board'] as List) v as int],
        turn = j['turn'] as int,
        starter = j['starter'] as int,
        winLine = (j['line'] as List?)?.map((e) => e as int).toList(),
        win = j['win'] as int,
        finished = j['fin'] == true,
        wins = [for (final v in j['wins'] as List) v as int],
        level = (j['lv'] as int?) ?? 0,
        hist = [for (final h in (j['hist'] as List?) ?? const [[], []]) [for (final v in h as List) v as int]],
        big = [for (final v in (j['big'] as List?) ?? List.filled(9, -1)) v as int],
        zone = (j['zone'] as int?) ?? -1,
        super.restore();

  static const lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  @override
  String get id => 'xo';

  final int level;
  List<int> board;
  int turn = 0;

  /// المتوسط: قطع كل لاعب بالترتيب (الأقدم أول)
  List<List<int>> hist = [[], []];

  /// الصعب: حالة كل لوحة صغيرة (-1 مفتوحة، 0/1 فاز بيها، 2 امتلت تعادل)، واللوحة المفروضة (-1 = أي وحدة)
  List<int> big = List.filled(9, -1);
  int zone = -1;

  bool get ultimate => level == 2;

  /// القطعة اللي راح تختفي بالحركة الجاية (المتوسط)، أو -1
  int get fading => level == 1 && !finished && hist[turn].length >= 3 ? hist[turn].first : -1;

  /// تنلعب هنا؟
  bool legal(int i) {
    if (finished || i < 0 || i >= board.length || board[i] >= 0) return false;
    if (!ultimate) return i != fading;
    final z = i ~/ 9;
    return big[z] < 0 && (zone < 0 || zone == z);
  }

  static int? lineOf(List<int> b, int p, [int off = 0]) {
    for (var k = 0; k < 8; k++) {
      final l = lines[k];
      if (b[off + l[0]] == p && b[off + l[1]] == p && b[off + l[2]] == p) return k;
    }
    return null;
  }
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
    if (player != turn || i is! int || !legal(i)) return;
    if (level == 1) {
      final h = hist[turn];
      if (h.length >= 3) {
        final old = h.removeAt(0);
        board[old] = -1;
        emit('fade', {'i': old, 'p': turn});
      }
      h.add(i);
    }
    board[i] = turn;
    emit('put', {'i': i, 'p': turn});
    if (ultimate) {
      final z = i ~/ 9;
      if (lineOf(board, turn, z * 9) != null) {
        big[z] = turn;
        emit('zone', {'z': z, 'p': turn});
      } else if (!board.sublist(z * 9, z * 9 + 9).contains(-1)) {
        big[z] = 2;
      }
      final k = lineOf(big, turn);
      if (k != null) return _win(lines[k]);
      if (!big.contains(-1)) return _draw();
      final next = i % 9;
      zone = big[next] < 0 ? next : -1;
    } else {
      final k = lineOf(board, turn);
      if (k != null) return _win(lines[k]);
      if (!board.contains(-1)) return _draw();
    }
    turn = 1 - turn;
  }

  void _win(List<int> l) {
    winLine = l;
    win = turn;
    wins[turn]++;
    finished = true;
    emit('win', {'p': turn});
  }

  void _draw() {
    win = -1;
    finished = true;
    emit('draw');
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
    board = List.filled(board.length, -1);
    hist = [[], []];
    big = List.filled(9, -1);
    zone = -1;
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
        'lv': level,
        'hist': hist,
        'big': big,
        'zone': zone,
      };
}
