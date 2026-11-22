import 'game_model.dart';
import 'spy_bank.dart';

/// قواعد "الجاسوس": 3-8 لاعبين، كل واحد بتلفونه وهم جالسين سوا ويسألون بعض بالصوت.
///
/// - الكل يشوف المكان إلا الجاسوس (والوضع الثاني `crazy` = جاسوسان إذا كانوا 6 فأكثر).
/// - بالدور: اللي عليه الدور يسأل أي واحد (مو اللي سأله قبل شوية)، والمسؤول يصير عليه الدور.
/// - أي لاعب يكدر يطلب تصويت. الوقت 8 دقايق وبعدها يبدأ التصويت تلقائياً.
/// - التصويت: إذا أغلبية صوّتت على جاسوس، يحزر المكان حزرة وحدة. غير هيج (بريء أو بدون أغلبية) الجاسوس ينجو.
/// - الجاسوس يكدر يحزر المكان بأي وقت (إذا صح يفوز، وإذا غلط الباقي يفوزون).
/// - النقاط: الجاسوس نقطتين إذا نجا أو حزر، والباقي نقطة إذا كشفوه ولا حزر.
/// - السيرفر يخفي المكان عن الجاسوس وهوية الجاسوس والأصوات عن الباقين لحد النهاية ([viewFor]).
class SpyModel extends GameModel {
  SpyModel({required super.players, required super.crazy, required super.seed})
      : out = List.filled(players, false),
        away = List.filled(players, false),
        votes = List.filled(players, -1),
        total = List.filled(players, 0) {
    _deal();
  }

  SpyModel.restore(super.j)
      : out = [for (final v in j['out'] as List) v == true],
        away = [for (final v in j['away'] as List) v == true],
        votes = [for (final v in j['votes'] as List) v as int],
        total = [for (final v in j['total'] as List) v as int],
        spies = [for (final v in j['spies'] as List) v as int],
        place = j['place'] as int,
        opts = [for (final v in j['opts'] as List) v as int],
        phase = j['ph'] as String,
        phaseAt = (j['pat'] as num).toDouble(),
        turn = j['turn'] as int,
        prev = j['prev'] as int,
        caller = j['caller'] as int,
        accused = j['acc'] as int,
        guessBy = j['gby'] as int,
        guess = j['gs'] as int,
        result = j['res'] as String,
        spiesWin = j['sw'] == true,
        round = j['round'] as int,
        super.restore();

  static const playTime = 480.0;
  static const voteTime = 30.0;
  static const guessTime = 25.0;
  static const countdown = 7.0;
  static const minPlayers = 3;
  static const optCount = 12;

  @override
  String get id => 'spy';

  /// المؤقتات بالثواني (4 مو أقل: الغرفة المحلية تحدد الفرق بين التكّات بربع ثانية)
  @override
  int get tickHz => 4;

  @override
  bool get secret => true;

  List<bool> out, away;

  /// صوت كل لاعب بالتصويت (-1 ما صوّت، -2 مخفي عنك)
  List<int> votes;

  /// مجموع النقاط بكل الجولات
  List<int> total;

  /// الجواسيس (للاعب العادي فاضية لحد النهاية)
  List<int> spies = [];

  /// رقم المكان ببنك الأماكن (-1 للجاسوس لحد النهاية)
  int place = 0;

  /// خيارات الحزرة (أرقام أماكن، بينها الصح)
  List<int> opts = [];

  /// count = شوف دورك، play = الأسئلة، vote = التصويت، guess = حزرة الجاسوس المكشوف، end = النتيجة
  String phase = 'count';
  double phaseAt = 0;

  /// اللي عليه الدور يسأل، واللي سأله قبل شوية (-1 = ماكو)
  int turn = 0, prev = -1;

  /// اللي طلب التصويت، واللي انكشف، والجاسوس اللي يحزر، وحزرته (رقم مكان)
  int caller = -1, accused = -1, guessBy = -1, guess = -1;

  /// سبب النهاية: found_ok / found_wrong / early_ok / early_wrong / innocent / nomajority / spy_left / abort
  String result = '';
  bool spiesWin = false;
  int round = 1;

  double get timeLeft {
    final lim = phase == 'play'
        ? playTime
        : phase == 'vote'
            ? voteTime
            : phase == 'guess'
                ? guessTime
                : countdown;
    return (lim - (time - phaseAt)).clamp(0, lim).toDouble();
  }

  List<int> get alive => [
        for (var p = 0; p < players; p++)
          if (!out[p]) p,
      ];

  @override
  bool get over => phase == 'end';

  @override
  List<int> get winners {
    if (!over || result == 'abort') return const [];
    return [
      for (var p = 0; p < players; p++)
        if (!out[p] && spies.contains(p) == spiesWin) p,
    ];
  }

  @override
  int get winner => winners.isEmpty ? -1 : winners.first;

  @override
  List<int> get scores => total;

  void _deal() {
    final live = _shuffle(alive);
    final k = crazy && live.length >= 6 ? 2 : 1;
    spies = live.take(k).toList()..sort();
    place = rng.nextInt(spyBank.length);
    final others = _shuffle([for (var i = 0; i < spyBank.length; i++) if (i != place) i]);
    opts = _shuffle([place, ...others.take(optCount - 1)]);
    votes = List.filled(players, -1);
    phase = 'count';
    phaseAt = time;
    turn = live[rng.nextInt(live.length)];
    prev = -1;
    caller = -1;
    accused = -1;
    guessBy = -1;
    guess = -1;
    result = '';
    spiesWin = false;
  }

  List<int> _shuffle(List<int> l) {
    for (var i = l.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final t = l[i];
      l[i] = l[j];
      l[j] = t;
    }
    return l;
  }

  void _startVote(int by) {
    caller = by;
    votes = List.filled(players, -1);
    phase = 'vote';
    phaseAt = time;
    emit('call', {'p': by});
  }

  bool get _allVoted {
    var present = 0;
    for (final p in alive) {
      if (away[p]) continue;
      present++;
      if (votes[p] == -1) return false;
    }
    return present > 0;
  }

  void _tally() {
    final c = List.filled(players, 0);
    for (final p in alive) {
      final t = votes[p];
      if (t >= 0 && t < players && !out[t] && t != p) c[t]++;
    }
    var best = 0;
    for (final v in c) {
      if (v > best) best = v;
    }
    final top = [
      for (var p = 0; p < players; p++)
        if (best > 0 && c[p] == best) p,
    ];
    if (top.length != 1 || best * 2 <= alive.length) {
      _finish('nomajority', true);
      return;
    }
    accused = top.first;
    if (spies.contains(accused)) {
      guessBy = accused;
      phase = 'guess';
      phaseAt = time;
      emit('found', {'p': accused});
    } else {
      _finish('innocent', true);
    }
  }

  void _guessResolve(int idx, bool early) {
    final ok = idx >= 0 && idx < spyBank.length && idx == place;
    guess = idx;
    _finish(early ? (ok ? 'early_ok' : 'early_wrong') : (ok ? 'found_ok' : 'found_wrong'), ok);
  }

  void _finish(String res, bool spyWon) {
    result = res;
    spiesWin = spyWon;
    if (res != 'abort') {
      for (final p in alive) {
        if (spies.contains(p) == spyWon) total[p] += spyWon ? 2 : 1;
      }
    }
    phase = 'end';
    phaseAt = time;
    emit('result', {'r': res});
  }

  void _nextTurn() {
    final cand = [
      for (final p in alive)
        if (!away[p] && p != turn && p != prev) p,
    ];
    final pool = cand.isNotEmpty ? cand : [for (final p in alive) if (p != turn) p];
    if (pool.isEmpty) return;
    prev = turn;
    turn = pool[rng.nextInt(pool.length)];
  }

  @override
  void input(int player, Map<String, dynamic> d) {
    if (player < 0 || player >= players || out[player]) return;
    final t = d['t'];
    switch (d['a']) {
      case 'ask':
        if (phase != 'play' || player != turn || t is! int || t < 0 || t >= players || out[t] || t == player) return;
        if (t == prev && alive.length > 2) return;
        prev = player;
        turn = t;
        emit('ask', {'from': player, 'to': t});
      case 'call':
        if (phase == 'play') _startVote(player);
      case 'vote':
        if (phase != 'vote' || t is! int || t < 0 || t >= players || out[t] || t == player) return;
        final first = votes[player] == -1;
        votes[player] = t;
        if (first) emit('voted', {'p': player});
        if (_allVoted) _tally();
      case 'guess':
        if (t is! int) return;
        if (phase == 'play' && spies.contains(player)) {
          _guessResolve(t, true);
        } else if (phase == 'guess' && player == guessBy) {
          _guessResolve(t, false);
        }
    }
  }

  @override
  void step(double dt) {
    switch (phase) {
      case 'count':
        if (time - phaseAt >= countdown) {
          phase = 'play';
          phaseAt = time;
          emit('play');
        }
      case 'play':
        if (time - phaseAt >= playTime) {
          _startVote(-1);
        } else if (out[turn] || away[turn]) {
          _nextTurn();
        }
      case 'vote':
        if (time - phaseAt >= voteTime) _tally();
      case 'guess':
        if (time - phaseAt >= guessTime) _guessResolve(-1, false);
    }
  }

  @override
  void connection(int player, bool on) {
    if (player < 0 || player >= players) return;
    away[player] = !on;
  }

  @override
  void forfeit(int player) {
    if (player < 0 || player >= players || out[player]) return;
    out[player] = true;
    votes[player] = -1;
    for (var p = 0; p < players; p++) {
      if (votes[p] == player) votes[p] = -1;
    }
    emit('left', {'p': player});
    if (phase == 'end') return;
    if (alive.length < minPlayers) {
      _finish('abort', false);
    } else if (spies.contains(player) && !spies.any((s) => !out[s])) {
      _finish('spy_left', false);
    } else if (phase == 'guess' && guessBy == player) {
      _finish('found_wrong', false);
    } else if (phase == 'vote' && _allVoted) {
      _tally();
    } else if (phase == 'play' && turn == player) {
      _nextTurn();
    }
  }

  @override
  void again() {
    total = List.of(total);
    round++;
    _deal();
    emit('again');
  }

  /// المكان للباقين، وكل واحد يعرف نفسه بس. الأصوات والجواسيس تنكشف بالنهاية.
  @override
  Map<String, dynamic> viewFor(int player) {
    final j = toJson();
    if (phase != 'end') {
      final spy = player >= 0 && spies.contains(player);
      j['place'] = player < 0 || spy ? -1 : place;
      j['spies'] = spy ? [player] : <int>[];
      j['votes'] = [
        for (var p = 0; p < players; p++) p == player || votes[p] == -1 ? votes[p] : -2,
      ];
    }
    j['rng'] = 0;
    return j;
  }

  @override
  Map<String, dynamic> save() => {
        'out': out,
        'away': away,
        'votes': votes,
        'total': total,
        'spies': spies,
        'place': place,
        'opts': opts,
        'ph': phase,
        'pat': phaseAt,
        'turn': turn,
        'prev': prev,
        'caller': caller,
        'acc': accused,
        'gby': guessBy,
        'gs': guess,
        'res': result,
        'sw': spiesWin,
        'round': round,
      };
}
