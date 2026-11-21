import 'game_model.dart';

/// قواعد الدومينو: 2 أو 4 لاعبين (الأربعة فريقين: كل اثنين متقابلين، اللاعب p بالفريق p % 2).
///
/// - 28 قطعة (0-0 لحد 6-6)، 7 لكل لاعب. بلاعبين: الباقي (14) للسحب.
/// - أول جولة يبدي اللي عنده 6-6 (أو أعلى مزدوجة) وبيها لازم. الجولات الجاية يبدي فائز الجولة بأي قطعة.
/// - ما عنده قطعة تنفع: بلاعبين يسحب لحد ما تطلع وحدة (إذا خلص السحب يمرّر)، بالأربعة يمرّر.
/// - تخلص الجولة إذا واحد خلّص قطعه (ياخذ مجموع نقاط الخصوم)، أو إذا تسكّرت (الأقل مجموع ياخذ مجموع الخصم).
///   بالأربعة النقاط للفريق، ومجموع الفريق = قطع الاثنين.
/// - الهدف 50 (crazy = 100). مؤقت الدور 30 ثانية ثم لعب تلقائي.
/// - السيرفر يخفي قطع الخصم والسحب ([viewFor]).
class DominoModel extends GameModel {
  DominoModel({required super.players, required super.crazy, required super.seed})
      : out = List.filled(players, false),
        hands = List.generate(players, (_) => <int>[]) {
    _deal();
  }

  DominoModel.restore(super.j)
      : out = [for (final v in j['out'] as List) v == true],
        hands = [for (final h in j['hands'] as List) [for (final t in h as List) t as int]],
        pile = [for (final t in j['pile'] as List) t as int],
        chain = [for (final t in j['chain'] as List) t as int],
        anchor = j['anc'] as int,
        turn = j['turn'] as int,
        turnAt = (j['ta'] as num).toDouble(),
        mustStart = j['must'] as int,
        side = [for (final v in j['ss'] as List) v as int],
        round = j['round'] as int,
        phase = j['ph'] as String,
        roundAt = (j['ra'] as num).toDouble(),
        lastKind = j['lk'] as String,
        lastSide = j['ls'] as int,
        lastPts = j['lp'] as int,
        lastBy = j['lb'] as int,
        lastSums = [for (final v in j['lsum'] as List) v as int],
        winSide = j['win'] as int,
        finished = j['fin'] == true,
        super.restore();

  static const turnTime = 30.0;
  static const roundTime = 4.5;
  static const passDelay = 1.2;

  /// القطعة i = (tileA[i], tileB[i])، مرتبة: 0-0، 0-1 ... 6-6
  static final List<int> tileA = [for (var a = 0; a <= 6; a++) for (var b = a; b <= 6; b++) a];
  static final List<int> tileB = [for (var a = 0; a <= 6; a++) for (var b = a; b <= 6; b++) b];
  static int pips(int t) => tileA[t] + tileB[t];
  static bool isDouble(int t) => tileA[t] == tileB[t];

  @override
  String get id => 'domino';
  @override
  int get tickHz => 4;
  @override
  bool get secret => true;
  @override
  bool get teams => players == 4;

  int get target => crazy ? 100 : 50;

  List<bool> out;

  /// قطع كل لاعب (بنسخة الخصم: -1 بمكان كل قطعة مخفية)
  List<List<int>> hands;

  /// قطع السحب (بلاعبين)
  List<int> pile = [];

  /// السلسلة من اليسار لليمين: [قطعة، الرقم اليسار، الرقم اليمين] لكل وحدة
  List<int> chain = [];

  /// مكان أول قطعة انلعبت بالسلسلة (للرسم: منها تتمدد للجهتين)
  int anchor = 0;
  int turn = 0;
  double turnAt = 0;

  /// أول جولة: القطعة اللي لازم يبدي بيها (-1 = أي قطعة)
  int mustStart = -1;

  /// نقاط الجهتين (لاعبين: كل لاعب جهة، أربعة: كل فريق جهة)
  List<int> side = [0, 0];
  int round = 0;

  /// play = اللعب، round = نتيجة الجولة تنعرض، والقطع كلها مكشوفة
  String phase = 'play';
  double roundAt = 0;

  /// آخر جولة: domino / block / tie، والجهة اللي أخذت، وكم، ومنو (اللي خلّص أو يبدي الجاية)
  String lastKind = '';
  int lastSide = -1, lastPts = 0, lastBy = -1;
  List<int> lastSums = [0, 0];
  int winSide = -1;
  bool finished = false;

  int sideOf(int p) => players == 4 ? p % 2 : p;
  int get chainLen => chain.length ~/ 3;
  int get leftEnd => chain.isEmpty ? -1 : chain[1];
  int get rightEnd => chain.isEmpty ? -1 : chain[chain.length - 1];
  int chainTile(int i) => chain[i * 3];
  int chainL(int i) => chain[i * 3 + 1];
  int chainR(int i) => chain[i * 3 + 2];

  double get timeLeft => (turnAt + turnTime - time).clamp(0, turnTime).toDouble();

  @override
  bool get over => finished;
  @override
  int get winner => winSide;
  @override
  List<int> get winners => winSide < 0 ? const [] : [for (var p = 0; p < players; p++) if (sideOf(p) == winSide) p];
  @override
  List<int> get scores => side;

  // ------------------------------------------------------------ القطع

  /// وين تنحط القطعة: 'l' / 'r' (فاضي = ما تنفع)
  List<String> sidesFor(int t) {
    if (t < 0) return const [];
    if (chain.isEmpty) return (mustStart < 0 || t == mustStart) ? const ['r'] : const [];
    final a = tileA[t], b = tileB[t];
    return [
      if (a == leftEnd || b == leftEnd) 'l',
      if (a == rightEnd || b == rightEnd) 'r',
    ];
  }

  List<int> playable(int p) => [for (final t in hands[p]) if (sidesFor(t).isNotEmpty) t];
  bool canMove(int p) => playable(p).isNotEmpty;
  int handSum(int p) => hands[p].fold(0, (s, t) => s + (t < 0 ? 0 : pips(t)));

  // ------------------------------------------------------------ الجولة

  void _deal() {
    final all = List.generate(28, (i) => i);
    for (var i = all.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final x = all[i];
      all[i] = all[j];
      all[j] = x;
    }
    hands = [for (var p = 0; p < players; p++) all.sublist(p * 7, p * 7 + 7)..sort()];
    pile = players == 4 ? [] : all.sublist(players * 7);
    chain = [];
    anchor = 0;
    phase = 'play';
    if (round == 0 || lastBy < 0) {
      // أعلى مزدوجة (أو أعلى قطعة إذا ماكو مزدوجة بالأيادي)
      var best = -1, who = 0;
      for (var p = 0; p < players; p++) {
        for (final t in hands[p]) {
          final score = (isDouble(t) ? 100 : 0) + pips(t);
          if (best < 0 || score > (isDouble(best) ? 100 : 0) + pips(best)) {
            best = t;
            who = p;
          }
        }
      }
      mustStart = best;
      turn = who;
    } else {
      mustStart = -1;
      turn = lastBy;
    }
    turnAt = time;
    emit('deal', {'turn': turn});
  }

  void _next() {
    turn = (turn + 1) % players;
    turnAt = time;
  }

  bool get _blocked {
    if (pile.isNotEmpty) return false;
    for (var p = 0; p < players; p++) {
      if (canMove(p)) return false;
    }
    return true;
  }

  void _play(int p, int t, String s) {
    hands[p].remove(t);
    final a = tileA[t], b = tileB[t];
    if (chain.isEmpty) {
      chain = [t, a, b];
      anchor = 0;
      mustStart = -1;
    } else if (s == 'l') {
      final other = a == leftEnd ? b : a;
      chain.insertAll(0, [t, other, leftEnd]);
      anchor++;
    } else {
      final other = a == rightEnd ? b : a;
      chain.addAll([t, rightEnd, other]);
    }
    emit('play', {'p': p, 't': t, 's': s});
    if (hands[p].isEmpty) {
      _endRound('domino', p);
    } else if (_blocked) {
      _endRound('block', p);
    } else {
      _next();
    }
  }

  /// يسحب لحد ما تطلع قطعة تنفع (أو يخلص السحب)
  void _draw(int p) {
    var n = 0;
    while (pile.isNotEmpty && !canMove(p)) {
      hands[p].add(pile.removeLast());
      n++;
    }
    hands[p].sort();
    if (n > 0) emit('draw', {'p': p, 'n': n});
    turnAt = time; // وقت جديد بعد السحب
    if (!canMove(p) && _blocked) _endRound('block', p);
  }

  void _pass(int p) {
    emit('pass', {'p': p});
    _next();
  }

  void _endRound(String kind, int by) {
    final sums = [0, 0];
    for (var p = 0; p < players; p++) {
      sums[sideOf(p)] += handSum(p);
    }
    var w = -1, pts = 0, starter = by;
    if (kind == 'domino') {
      w = sideOf(by);
      pts = sums[1 - w];
    } else if (sums[0] != sums[1]) {
      w = sums[0] < sums[1] ? 0 : 1;
      pts = sums[1 - w];
      // يبدي الجولة الجاية: الأقل مجموع بالجهة الفايزة
      var best = 1 << 30;
      for (var p = 0; p < players; p++) {
        if (sideOf(p) == w && handSum(p) < best) {
          best = handSum(p);
          starter = p;
        }
      }
    } else {
      kind = 'tie';
    }
    if (w >= 0) side[w] += pts;
    lastKind = kind;
    lastSide = w;
    lastPts = pts;
    lastBy = starter;
    lastSums = sums;
    phase = 'round';
    roundAt = time;
    emit('round', {'k': kind, 'side': w, 'pts': pts, 'by': by});
  }

  /// لعب تلقائي (خلص الوقت، أو اللاعب طلع): أول قطعة تنفع، وإلا يسحب، وإلا يمرّر
  void _auto(int p) {
    if (!canMove(p) && pile.isNotEmpty) _draw(p);
    if (phase != 'play') return;
    final ok = playable(p);
    if (ok.isNotEmpty) {
      _play(p, ok.first, sidesFor(ok.first).first);
    } else {
      _pass(p);
    }
  }

  // ------------------------------------------------------------ الحركات

  @override
  void input(int player, Map<String, dynamic> d) {
    if (finished || phase != 'play' || player != turn || out[player]) return;
    switch (d['a']) {
      case 'play':
        final t = (d['t'] as num?)?.toInt() ?? -1;
        final s = d['s'] == 'l' ? 'l' : 'r';
        if (!hands[player].contains(t) || !sidesFor(t).contains(s)) return;
        _play(player, t, s);
      case 'draw':
        if (canMove(player) || pile.isEmpty) return;
        _draw(player);
    }
  }

  @override
  void step(double dt) {
    if (finished) return;
    if (phase == 'round') {
      if (time - roundAt < roundTime) return;
      final best = side[0] >= side[1] ? 0 : 1;
      if (side[best] >= target && side[0] != side[1]) {
        winSide = best;
        finished = true;
        emit('win', {'side': best});
        return;
      }
      round++;
      _deal();
      return;
    }
    final p = turn;
    if (out[p] || time - turnAt >= turnTime) {
      _auto(p);
    } else if (!canMove(p) && pile.isEmpty && time - turnAt >= passDelay) {
      _pass(p);
    }
  }

  @override
  void forfeit(int player) {
    if (player < 0 || player >= players || out[player]) return;
    out[player] = true;
    emit('left', {'p': player});
    if (finished) return;
    // بلاعبين: الثاني يفوز. بالأربعة: نلعب عنه تلقائياً، وإذا طلع الفريق كله الثاني يفوز
    for (final s in [0, 1]) {
      final left = [for (var p = 0; p < players; p++) if (sideOf(p) == s && !out[p]) p];
      if (left.isEmpty) {
        winSide = 1 - s;
        finished = true;
        emit('win', {'side': winSide});
        return;
      }
    }
  }

  @override
  void again() {
    side = [0, 0];
    round = 0;
    lastBy = -1;
    lastKind = '';
    lastSide = -1;
    lastPts = 0;
    winSide = -1;
    finished = false;
    _deal();
  }

  /// الخصم يشوف عدد قطعك بس، والسحب مخفي (إلا بنتيجة الجولة)
  @override
  Map<String, dynamic> viewFor(int player) {
    final j = toJson();
    j['rng'] = 0;
    if (phase == 'play' && !finished) {
      j['hands'] = [
        for (var p = 0; p < players; p++) p == player ? hands[p] : List.filled(hands[p].length, -1),
      ];
    }
    j['pile'] = List.filled(pile.length, -1);
    return j;
  }

  @override
  Map<String, dynamic> save() => {
        'out': out,
        'hands': hands,
        'pile': pile,
        'chain': chain,
        'anc': anchor,
        'turn': turn,
        'ta': turnAt,
        'must': mustStart,
        'ss': side,
        'round': round,
        'ph': phase,
        'ra': roundAt,
        'lk': lastKind,
        'ls': lastSide,
        'lp': lastPts,
        'lb': lastBy,
        'lsum': lastSums,
        'win': winSide,
        'fin': finished,
      };
}
