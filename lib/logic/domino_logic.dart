import 'game_model.dart';

/// قواعد الدومينو: 2 أو 4 لاعبين (الأربعة فريقين: كل اثنين متقابلين، اللاعب p بالفريق p % 2).
///
/// وضعين:
/// - **الكلاسيكي** (اللي يلعبوه بالبيوت): النقاط بس بآخر الجولة. الهدف 50 (crazy = 100).
/// - **الخمسات** (`fives`): أول قطعة بالجولة أعلى دبل (السبينر)، يتفرع لأربع جهات (فوق وجوه
///   يفتحن بعد ما ينلعب على يمينه ويساره). كل ما مجموع الأطراف المفتوحة من مضاعفات 5 ينحسب للي لعب.
///   الدبل بالطرف ينحسب كامل (وجهينه)، والسبينر ينحسب كامل لحد ما ينلعب على جهتيه.
///   آخر الجولة: مجموع قطع الخصم مقرّب لأقرب 5. الهدف [goal] (100/150/200)، وأول من يوصله يفوز فوراً.
///
/// - 28 قطعة (0-0 لحد 6-6)، 7 لكل لاعب. بلاعبين: الباقي (14) للسحب (المخزن).
/// - الكلاسيكي: أول جولة يبدي اللي عنده أعلى دبل وبيه لازم، والجاية يبديها الفايز بأي قطعة.
/// - ما عنده قطعة تنفع: بلاعبين يسحب قطعة قطعة من المخزن (إذا خلص يمرّر)، بالأربعة يمرّر.
/// - تخلص الجولة إذا واحد خلّص قطعه (ياخذ مجموع الخصوم)، أو تسكّرت (الأقل مجموع ياخذ مجموع الخصم).
/// - بعد الجولة: الكل يضغط "الجولة التالية" (أو تبدي وحدها بعد [roundTime]).
/// - مؤقت الدور 30 ثانية ثم لعب تلقائي. السيرفر يخفي قطع الخصم والمخزن ([viewFor]).
class DominoModel extends GameModel {
  /// [level] (0 سهل، 1 متوسط، 2 صعب) يحدد كل شي: سهل = الكلاسيكي 50، متوسط = الخمسات 100،
  /// صعب = الخمسات 200 ودور 15 ثانية وبدون إضاءة الأحجار الصالحة. -1 = القديم (fives/goal/crazy).
  DominoModel({required super.players, required super.crazy, required super.seed, bool fives = false, int? goal, this.level = -1})
      : fives = level >= 0 ? level >= 1 : fives,
        goal = level >= 0 ? const [50, 100, 200][level.clamp(0, 2)] : (goal ?? (fives ? 100 : (crazy ? 100 : 50))),
        turnTime = level == 2 ? 15.0 : 30.0,
        out = List.filled(players, false),
        nextOk = List.filled(players, false),
        hands = List.generate(players, (_) => <int>[]) {
    _deal();
  }

  DominoModel.restore(super.j)
      : fives = j['fv'] == true,
        level = (j['lv'] as num?)?.toInt() ?? -1,
        turnTime = (j['tt'] as num?)?.toDouble() ?? 30.0,
        goal = (j['goal'] as num?)?.toInt() ?? (j['crazy'] == true ? 100 : 50),
        out = [for (final v in j['out'] as List) v == true],
        nextOk = [for (final v in (j['nx'] as List? ?? const [])) v == true],
        hands = [for (final h in j['hands'] as List) [for (final t in h as List) t as int]],
        pile = [for (final t in j['pile'] as List) t as int],
        chain = [for (final t in j['chain'] as List) t as int],
        up = [for (final t in (j['up'] as List? ?? const [])) t as int],
        dn = [for (final t in (j['dn'] as List? ?? const [])) t as int],
        anchor = j['anc'] as int,
        turn = j['turn'] as int,
        turnAt = (j['ta'] as num).toDouble(),
        mustStart = j['must'] as int,
        side = [for (final v in j['ss'] as List) v as int],
        roundPts = [for (final v in (j['rp'] as List? ?? const [0, 0])) v as int],
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
        super.restore() {
    if (nextOk.length != players) nextOk = List.filled(players, false);
  }

  /// مؤقت الدور الافتراضي (الصعب أقصر: [turnTime])
  static const turnTimeDefault = 30.0;
  static const roundTime = 20.0;
  static const passDelay = 1.2;

  /// الأهداف المسموحة بالخمسات
  static const fivesGoals = [100, 150, 200];

  /// القطعة i = (tileA[i], tileB[i])، مرتبة: 0-0، 0-1 ... 6-6
  static final List<int> tileA = [for (var a = 0; a <= 6; a++) for (var b = a; b <= 6; b++) a];
  static final List<int> tileB = [for (var a = 0; a <= 6; a++) for (var b = a; b <= 6; b++) b];
  static int pips(int t) => tileA[t] + tileB[t];
  static bool isDouble(int t) => tileA[t] == tileB[t];

  /// رقم القطعة من وجهيها
  static int tileOf(int a, int b) {
    final lo = a < b ? a : b, hi = a < b ? b : a;
    var i = 0;
    for (var x = 0; x < lo; x++) {
      i += 7 - x;
    }
    return i + (hi - lo);
  }

  @override
  String get id => 'domino';
  @override
  int get tickHz => 4;

  /// لعبة دور: أونلاين تنعرض الحركة أول ما توصل (بدون تأخير)
  @override
  bool get buffered => false;
  @override
  bool get secret => true;
  @override
  bool get teams => players == 4;

  /// وضع الخمسات، والهدف
  final bool fives;
  final int goal;
  final int level;
  final double turnTime;

  /// الأحجار الصالحة تضوي؟ (الصعب لا)
  bool get hints => level != 2;
  int get target => goal;

  List<bool> out;

  /// منو ضغط "الجولة التالية"
  List<bool> nextOk;

  /// قطع كل لاعب (بنسخة الخصم: -1 بمكان كل قطعة مخفية)
  List<List<int>> hands;

  /// المخزن (بلاعبين)
  List<int> pile = [];

  /// الخط الأساسي من اليسار لليمين: [قطعة، الرقم اليسار، الرقم اليمين] لكل وحدة
  List<int> chain = [];

  /// فرعين السبينر (بالخمسات): [قطعة، الرقم القريب، الرقم البعيد] من السبينر للبرا
  List<int> up = [], dn = [];

  /// مكان أول قطعة انلعبت بالخط (منها يتمدد للجهتين، وهي السبينر إذا دبل بالخمسات)
  int anchor = 0;
  int turn = 0;
  double turnAt = 0;

  /// القطعة اللي لازم يبدي بيها (-1 = أي قطعة)
  int mustStart = -1;

  /// نقاط الجهتين (لاعبين: كل لاعب جهة، أربعة: كل فريق جهة)، واللي انربح بهالجولة
  List<int> side = [0, 0];
  List<int> roundPts = [0, 0];
  int round = 0;

  /// play = اللعب، round = نتيجة الجولة تنعرض، والقطع كلها مكشوفة
  String phase = 'play';
  double roundAt = 0;

  /// آخر جولة: domino / block / tie / reach (وصل الهدف بنص الجولة)، والجهة، وكم، ومنو
  String lastKind = '';
  int lastSide = -1, lastPts = 0, lastBy = -1;
  List<int> lastSums = [0, 0];
  int winSide = -1;
  bool finished = false;

  int sideOf(int p) => players == 4 ? p % 2 : p;
  int get chainLen => chain.length ~/ 3;
  int get leftEnd => chain.isEmpty ? -1 : chain[1];
  int get rightEnd => chain.isEmpty ? -1 : chain[chain.length - 1];
  int get upEnd => up.isEmpty ? (chain.isEmpty ? -1 : chain[anchor * 3 + 1]) : up[up.length - 1];
  int get dnEnd => dn.isEmpty ? (chain.isEmpty ? -1 : chain[anchor * 3 + 1]) : dn[dn.length - 1];
  int chainTile(int i) => chain[i * 3];
  int chainL(int i) => chain[i * 3 + 1];
  int chainR(int i) => chain[i * 3 + 2];

  /// أول قطعة دبل بالخمسات = سبينر
  bool get spinner => fives && chain.isNotEmpty && isDouble(chainTile(anchor));

  /// فوق وجوه يفتحن بعد ما ينلعب يمين ويسار السبينر
  bool get crossOpen => spinner && anchor > 0 && anchor < chainLen - 1;

  /// الأطراف المفتوحة
  List<String> get arms => chain.isEmpty ? const [] : (crossOpen ? const ['l', 'r', 'u', 'd'] : const ['l', 'r']);

  int endOf(String arm) => switch (arm) { 'l' => leftEnd, 'r' => rightEnd, 'u' => upEnd, _ => dnEnd };

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

  /// وين تنحط القطعة: 'l' / 'r' / 'u' / 'd' (فاضي = ما تنفع)
  List<String> sidesFor(int t) {
    if (t < 0 || t >= 28) return const [];
    if (chain.isEmpty) return (mustStart < 0 || t == mustStart) ? const ['r'] : const [];
    final a = tileA[t], b = tileB[t];
    return [
      for (final arm in arms)
        if (a == endOf(arm) || b == endOf(arm)) arm,
    ];
  }

  List<int> playable(int p) => [for (final t in hands[p]) if (sidesFor(t).isNotEmpty) t];
  bool canMove(int p) => playable(p).isNotEmpty;
  int handSum(int p) => hands[p].fold(0, (s, t) => s + (t < 0 ? 0 : pips(t)));

  /// مجموع الأطراف المفتوحة (نقاط الخمسات)
  int get endsSum => endsSumOf(chain, up, dn, anchor);

  static int endsSumOf(List<int> chain, List<int> up, List<int> dn, int anchor) {
    if (chain.isEmpty) return 0;
    final n = chain.length ~/ 3;
    final first = chain[anchor * 3];
    final spin = isDouble(first);
    if (n == 1 && up.isEmpty && dn.isEmpty) return pips(first);
    var s = 0;
    // اليسار
    if (anchor == 0) {
      s += spin ? pips(first) : chain[1];
    } else {
      s += isDouble(chain[0]) ? chain[1] * 2 : chain[1];
    }
    // اليمين
    if (anchor == n - 1) {
      s += spin ? pips(first) : chain[chain.length - 1];
    } else {
      final t = chain[chain.length - 3];
      s += isDouble(t) ? chain[chain.length - 1] * 2 : chain[chain.length - 1];
    }
    for (final arm in [up, dn]) {
      if (arm.isEmpty) continue;
      final t = arm[arm.length - 3];
      s += isDouble(t) ? arm[arm.length - 1] * 2 : arm[arm.length - 1];
    }
    return s;
  }

  /// كم تجيب هاي الحركة بالخمسات (0 = ولا شي). للبوت والواجهة.
  int scoreIfPlayed(int t, String arm) {
    if (!fives) return 0;
    final c = List.of(chain), u = List.of(up), d = List.of(dn);
    var anc = anchor;
    final a = tileA[t], b = tileB[t];
    if (c.isEmpty) {
      c.addAll([t, a, b]);
      anc = 0;
    } else {
      final e = endOf(arm);
      final other = a == e ? b : a;
      switch (arm) {
        case 'l':
          c.insertAll(0, [t, other, e]);
          anc++;
        case 'r':
          c.addAll([t, e, other]);
        case 'u':
          u.addAll([t, e, other]);
        default:
          d.addAll([t, e, other]);
      }
    }
    final s = endsSumOf(c, u, d, anc);
    return s > 0 && s % 5 == 0 ? s : 0;
  }

  static int round5(int x) => ((x + 2) ~/ 5) * 5;

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
    up = [];
    dn = [];
    anchor = 0;
    phase = 'play';
    roundPts = [0, 0];
    nextOk = List.filled(players, false);
    if (fives || round == 0 || lastBy < 0) {
      // أعلى دبل (أو أعلى قطعة إذا ماكو دبل بالأيادي). بالخمسات كل جولة تبدي بالسبينر بالنص.
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
      s = 'r';
    } else {
      final e = endOf(s);
      final other = a == e ? b : a;
      switch (s) {
        case 'l':
          chain.insertAll(0, [t, other, e]);
          anchor++;
        case 'r':
          chain.addAll([t, e, other]);
        case 'u':
          up.addAll([t, e, other]);
        default:
          dn.addAll([t, e, other]);
      }
    }
    var pts = 0;
    if (fives) {
      final sum = endsSum;
      if (sum > 0 && sum % 5 == 0) {
        pts = sum;
        side[sideOf(p)] += pts;
        roundPts[sideOf(p)] += pts;
      }
    }
    emit('play', {'p': p, 't': t, 's': s, if (pts > 0) 'pts': pts});
    if (fives && side[sideOf(p)] >= goal) {
      _endRound('reach', p);
    } else if (hands[p].isEmpty) {
      _endRound('domino', p);
    } else if (_blocked) {
      _endRound('block', p);
    } else {
      _next();
    }
  }

  /// يسحب قطعة وحدة من المخزن
  void _drawOne(int p) {
    if (pile.isEmpty) return;
    hands[p].add(pile.removeLast());
    hands[p].sort();
    emit('draw', {'p': p, 'n': 1});
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
    if (kind == 'reach') {
      w = sideOf(by);
    } else if (kind == 'domino') {
      w = sideOf(by);
      pts = sums[1 - w];
    } else if (sums[0] != sums[1]) {
      w = sums[0] < sums[1] ? 0 : 1;
      pts = fives ? sums[1 - w] - sums[w] : sums[1 - w];
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
    if (fives) pts = round5(pts);
    if (w >= 0) {
      side[w] += pts;
      roundPts[w] += pts;
    }
    lastKind = kind;
    lastSide = w;
    lastPts = pts;
    lastBy = starter;
    lastSums = sums;
    phase = 'round';
    roundAt = time;
    nextOk = List.filled(players, false);
    emit('round', {'k': kind, 'side': w, 'pts': pts, 'by': by});
  }

  /// لعب تلقائي (خلص الوقت، أو اللاعب طلع): أحسن قطعة، وإلا يسحب، وإلا يمرّر
  void _auto(int p) {
    while (phase == 'play' && !canMove(p) && pile.isNotEmpty) {
      _drawOne(p);
    }
    if (phase != 'play') return;
    final mv = bestQuick(p);
    if (mv != null) {
      _play(p, mv.$1, mv.$2);
    } else {
      _pass(p);
    }
  }

  /// حركة بسيطة: أعلى نقاط بالخمسات، وإلا أثقل قطعة
  (int, String)? bestQuick(int p) {
    (int, String)? best;
    var bestV = -1;
    for (final t in hands[p]) {
      for (final s in sidesFor(t)) {
        final v = scoreIfPlayed(t, s) * 100 + pips(t);
        if (v > bestV) {
          bestV = v;
          best = (t, s);
        }
      }
    }
    return best;
  }

  void _maybeNext() {
    if (phase != 'round' || finished) return;
    for (var p = 0; p < players; p++) {
      if (!out[p] && !nextOk[p]) return;
    }
    _advanceRound();
  }

  void _advanceRound() {
    final best = side[0] >= side[1] ? 0 : 1;
    if (side[best] >= goal && side[0] != side[1]) {
      winSide = best;
      finished = true;
      emit('win', {'side': best});
      return;
    }
    round++;
    _deal();
  }

  // ------------------------------------------------------------ الحركات

  @override
  void input(int player, Map<String, dynamic> d) {
    if (finished || player < 0 || player >= players || out[player]) return;
    if (d['a'] == 'next') {
      if (phase == 'round') {
        nextOk[player] = true;
        _maybeNext();
      }
      return;
    }
    if (phase != 'play' || player != turn) return;
    switch (d['a']) {
      case 'play':
        final t = (d['t'] as num?)?.toInt() ?? -1;
        final s = d['s'];
        if (s is! String || !hands[player].contains(t) || !sidesFor(t).contains(s)) return;
        _play(player, t, s);
      case 'draw':
        if (canMove(player) || pile.isEmpty) return;
        _drawOne(player);
    }
  }

  @override
  void step(double dt) {
    if (finished) return;
    if (phase == 'round') {
      if (time - roundAt >= roundTime) _advanceRound();
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
    _maybeNext();
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

  /// الخصم يشوف عدد قطعك بس، والمخزن مخفي (إلا بنتيجة الجولة)
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
        'fv': fives,
        'lv': level,
        'tt': turnTime,
        'goal': goal,
        'out': out,
        'nx': nextOk,
        'hands': hands,
        'pile': pile,
        'chain': chain,
        'up': up,
        'dn': dn,
        'anc': anchor,
        'turn': turn,
        'ta': turnAt,
        'must': mustStart,
        'ss': side,
        'rp': roundPts,
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
