import 'game_model.dart';
import 'whois_bank.dart';

/// قواعد "منو بينا؟": 3-8 لاعبين، 8 أسئلة مضحكة. بدون فائز ونقاط (للضحك).
///
/// - كل سؤال 15 ثانية: كل لاعب يصوّت بسرية على لاعب ثاني (مو نفسه). ممكن يغيّر صوته قبل ما ينتهي الوقت.
/// - الكشف: الأكثر أصواتاً ياخذ "لقب الجولة" (التعادل = كل المتعادلين). من ما صوّت = ممتنع.
/// - بالنهاية كل لاعب ياخذ لقب نهائي: لقب السؤال اللي جاب بيه أكثر أصوات (وإذا ما فاز بشي لقب عام).
/// - `crazy` = "كشف الأصوات": منو صوّت لمنو يظهر وقت الكشف (افتراضياً الأصوات سرية).
/// - الأصوات سرية: [viewFor] يخفي أصوات الباقين لحد الكشف. اللي طلع نهائياً أصواته تنحذف،
///   وإذا بقى أقل من 3 تنتهي اللعبة.
class WhoisModel extends GameModel {
  WhoisModel({required super.players, required super.crazy, required super.seed})
      : out = List.filled(players, false),
        away = List.filled(players, false),
        votes = List.filled(players, -1),
        tally = List.filled(players, 0),
        total = List.filled(players, 0),
        won = List.generate(players, (_) => <int>[]),
        agree = List.filled(players, 0),
        cast = List.filled(players, 0),
        skip = List.filled(players, 0),
        pairs = List.filled(players * players, 0) {
    _pick();
  }

  WhoisModel.restore(super.j)
      : out = [for (final v in j['out'] as List) v == true],
        away = [for (final v in j['away'] as List) v == true],
        votes = [for (final v in j['votes'] as List) v as int],
        tally = [for (final v in j['tally'] as List) v as int],
        total = [for (final v in j['total'] as List) v as int],
        won = [
          for (final l in j['won'] as List) [for (final v in l as List) v as int]
        ],
        qs = [for (final v in j['qs'] as List) v as int],
        qi = j['qi'] as int,
        phase = j['ph'] as String,
        phaseAt = (j['pat'] as num).toDouble(),
        top = [for (final v in j['top'] as List) v as int],
        agree = [for (final v in j['agree'] as List) v as int],
        cast = [for (final v in j['cast'] as List) v as int],
        skip = [for (final v in j['skip'] as List) v as int],
        pairs = [for (final v in j['pairs'] as List) v as int],
        unan = [for (final v in j['unan'] as List) v as int],
        super.restore();

  static const questions = 8;
  static const voteTime = 15.0;
  static const revealTime = 5.5;
  static const countdown = 2.6;
  static const minPlayers = 3;

  @override
  String get id => 'whois';

  /// بالدور، بس المؤقت يحتاج تكّات (قليلة تكفي)
  @override
  int get tickHz => 4;

  @override
  bool get secret => true;

  /// لعبة للضحك: ما تنحسب فوز وخسارة
  @override
  bool get scored => false;

  List<bool> out, away;

  /// صوت كل لاعب (رقم اللاعب، -1 = ما صوّت). المخفي عنك = -2 (صوّت بس ما تعرف لمنو).
  List<int> votes;

  /// أصوات كل لاعب بهذا السؤال، ومجموعها بكل الأسئلة
  List<int> tally, total;

  /// الأسئلة اللي فاز بيها كل لاعب: أزواج (رقم السؤال بالبنك، عدد الأصوات)
  List<List<int>> won;

  List<int> qs = [];
  int qi = 0;

  /// count = عدّ تنازلي بالبداية، vote = التصويت، reveal = كشف الجولة، final = الألقاب النهائية
  String phase = 'count';
  double phaseAt = 0;

  /// أصحاب لقب الجولة الحالية
  List<int> top = [];

  // ---- للإحصائيات المضحكة بالنهاية (تنخفى لحد النهاية حتى ما تكشف الأصوات)
  /// كم مرة صوّت ويا الأغلبية (لصاحب اللقب)، كم مرة صوّت، كم مرة امتنع
  List<int> agree, cast, skip;

  /// بوضع "كشف الأصوات" بس: كم مرة a صوّت لـ b (pairs[a * players + b])
  List<int> pairs;

  /// أسئلة انحسمت بالإجماع: أزواج (رقم السؤال بالبنك، اللاعب)
  List<int> unan = [];

  double get timeLeft => (voteTime - (time - phaseAt)).clamp(0, voteTime).toDouble();
  (String, String) get current => whoisBank[qs[qi]];

  List<int> get alive => [
        for (var p = 0; p < players; p++)
          if (!out[p]) p,
      ];

  /// أصوات الجميع تنكشف (وضع كشف الأصوات)
  bool get showVoters => crazy;

  @override
  bool get over => phase == 'final';
  @override
  int get winner => -1;
  @override
  List<int> get scores => total;

  void _pick() {
    final idx = List.generate(whoisBank.length, (i) => i);
    for (var i = idx.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final t = idx[i];
      idx[i] = idx[j];
      idx[j] = t;
    }
    qs = idx.take(questions).toList();
    qi = 0;
    phase = 'count';
    phaseAt = time;
  }

  void _ask() {
    votes = List.filled(players, -1);
    tally = List.filled(players, 0);
    top = [];
    phase = 'vote';
    phaseAt = time;
    emit('q', {'i': qi});
  }

  /// كل الحاضرين صوّتوا؟ (إذا الكل غايب، ننتظر الوقت حتى ما تخلص الأسئلة بدون أحد)
  bool get _allVoted {
    var present = 0;
    for (final p in alive) {
      if (away[p]) continue;
      present++;
      if (votes[p] == -1) return false;
    }
    return present > 0;
  }

  void _reveal() {
    tally = List.filled(players, 0);
    for (var p = 0; p < players; p++) {
      final t = votes[p];
      if (out[p] || t < 0 || t >= players || out[t] || t == p) continue;
      tally[t]++;
    }
    var best = 0;
    for (final v in tally) {
      if (v > best) best = v;
    }
    top = best == 0
        ? []
        : [
            for (var p = 0; p < players; p++)
              if (tally[p] == best) p,
          ];
    for (var p = 0; p < players; p++) {
      total[p] += tally[p];
    }
    for (final p in top) {
      won[p].addAll([qs[qi], best]);
    }
    // الإحصائيات
    final live = alive;
    for (final p in live) {
      final t = votes[p];
      if (t < 0 || t >= players || out[t] || t == p) {
        skip[p]++;
        continue;
      }
      cast[p]++;
      if (top.contains(t)) agree[p]++;
      if (crazy) pairs[p * players + t]++;
    }
    if (top.length == 1 && live.length >= 3 && tally[top.first] == live.length - 1) {
      unan.addAll([qs[qi], top.first]);
    }
    phase = 'reveal';
    phaseAt = time;
    emit('reveal', {'top': top});
  }

  void _final() {
    phase = 'final';
    phaseAt = time;
    emit('final');
  }

  /// اللقب النهائي للاعب: لقب السؤال اللي جاب بيه أكثر أصوات (التعادل: الأسبق)
  String finalTitleOf(int p) {
    if (p < 0 || p >= players || won[p].isEmpty) return 'خفيف الظل';
    var bestV = -1, bestQ = won[p][0];
    for (var i = 0; i + 1 < won[p].length; i += 2) {
      if (won[p][i + 1] > bestV) {
        bestV = won[p][i + 1];
        bestQ = won[p][i];
      }
    }
    return whoisBank[bestQ].$2;
  }

  /// نجم اللمّة: أكثر واحد جاب أصوات بالمباراة (-1 = ماكو أو تعادل)
  int get star => _uniqueMax([for (final p in alive) (p, total[p])], 1);

  /// إذا واحد بس عنده أعلى قيمة (وهي >= at least) يرجع رقمه، وإلا -1
  int _uniqueMax(List<(int, int)> xs, int atLeast) {
    var best = -1, who = -1, ties = 0;
    for (final (p, v) in xs) {
      if (v > best) {
        best = v;
        who = p;
        ties = 1;
      } else if (v == best) {
        ties++;
      }
    }
    return ties == 1 && best >= atLeast ? who : -1;
  }

  /// إحصائيات مضحكة بالنهاية: (النوع، لاعب، رقم ثاني، عدد). الأنواع:
  /// unan = بالإجماع (b = السؤال)، pair = a صوّت لـ b (كشف الأصوات بس)، star = نجم اللمّة،
  /// rebel = المتمرّد، herd = يفكّر مثل الأغلبية، zero = المظلوم (ولا صوت)، skip = أبو الامتناع.
  List<(String, int, int, int)> get facts {
    final out = <(String, int, int, int)>[];
    final live = alive;
    for (var i = 0; i + 1 < unan.length; i += 2) {
      if (!this.out[unan[i + 1]]) {
        out.add(('unan', unan[i + 1], unan[i], 0));
        break;
      }
    }
    if (crazy) {
      var bn = 0, ba = -1, bb = -1;
      for (final a in live) {
        for (final b in live) {
          final n = pairs[a * players + b];
          if (n > bn) {
            bn = n;
            ba = a;
            bb = b;
          }
        }
      }
      if (bn >= 3) out.add(('pair', ba, bb, bn));
    }
    final s = star;
    if (s >= 0) out.add(('star', s, -1, total[s]));
    // المتمرّد: أقل اتفاق ويا الأغلبية (لازم صوّت 4 مرات على الأقل)
    final voters = [for (final p in live) if (cast[p] >= 4) p];
    final rebel = _uniqueMax([for (final p in voters) (p, -agree[p])], -999);
    if (rebel >= 0 && agree[rebel] * 3 <= cast[rebel]) out.add(('rebel', rebel, -1, agree[rebel]));
    final herd = _uniqueMax([for (final p in voters) if (p != rebel) (p, agree[p])], 3);
    if (herd >= 0) out.add(('herd', herd, -1, agree[herd]));
    final zero = [for (final p in live) if (total[p] == 0) p];
    if (zero.length == 1) out.add(('zero', zero.first, -1, 0));
    final sk = _uniqueMax([for (final p in live) (p, skip[p])], 2);
    if (sk >= 0) out.add(('skip', sk, -1, skip[sk]));
    return out;
  }

  @override
  void input(int player, Map<String, dynamic> d) {
    if (d['a'] != 'vote' || phase != 'vote' || player < 0 || player >= players || out[player]) return;
    final t = d['t'];
    if (t is! int || t < 0 || t >= players || t == player || out[t]) return;
    final first = votes[player] == -1;
    votes[player] = t;
    if (first) emit('voted', {'p': player});
    if (_allVoted) _reveal();
  }

  @override
  void step(double dt) {
    switch (phase) {
      case 'count':
        if (time - phaseAt >= countdown) _ask();
      case 'vote':
        if (time - phaseAt >= voteTime) _reveal();
      case 'reveal':
        if (time - phaseAt >= revealTime) {
          if (qi >= qs.length - 1) {
            _final();
          } else {
            qi++;
            _ask();
          }
        }
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
    if (phase == 'final') return;
    if (alive.length < minPlayers) {
      _final();
    } else if (phase == 'vote' && _allVoted) {
      _reveal();
    }
  }

  @override
  void again() {
    votes = List.filled(players, -1);
    tally = List.filled(players, 0);
    total = List.filled(players, 0);
    won = List.generate(players, (_) => <int>[]);
    agree = List.filled(players, 0);
    cast = List.filled(players, 0);
    skip = List.filled(players, 0);
    pairs = List.filled(players * players, 0);
    unan = [];
    top = [];
    _pick();
    emit('again');
  }

  /// كل واحد يشوف صوته بس. أصوات الباقين تنكشف بالكشف إذا وضع "كشف الأصوات" شغال.
  @override
  Map<String, dynamic> viewFor(int player) {
    final j = toJson();
    final open = crazy && (phase == 'reveal' || phase == 'final');
    if (!open) {
      j['votes'] = [
        for (var p = 0; p < players; p++)
          p == player || votes[p] == -1 ? votes[p] : -2,
      ];
    }
    // الإحصائيات تكشف منو صوّت ويا الأغلبية: تنخفى لحد النهاية
    if (phase != 'final') {
      j['agree'] = List.filled(players, 0);
      j['cast'] = List.filled(players, 0);
      j['pairs'] = List.filled(players * players, 0);
    }
    j['rng'] = 0;
    return j;
  }

  @override
  Map<String, dynamic> save() => {
        'out': out,
        'away': away,
        'votes': votes,
        'tally': tally,
        'total': total,
        'won': won,
        'qs': qs,
        'qi': qi,
        'ph': phase,
        'pat': phaseAt,
        'top': top,
        'agree': agree,
        'cast': cast,
        'skip': skip,
        'pairs': pairs,
        'unan': unan,
      };
}
