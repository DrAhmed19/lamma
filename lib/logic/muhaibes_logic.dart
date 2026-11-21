import 'game_model.dart';

/// قواعد "المحيبس": فريقين (اللاعب p بالفريق p % 2)، 4-8 لاعبين. أول فريق يوصل 15 نقطة يفوز.
///
/// - الفريق المخبّي: واحد منهم (بالدور) يختار بسرية بيا قبضة يصير المحبس. فريقه بس يعرف.
///   كل لاعب بقبضتين: القبضة f = لاعب f ~/ 2، يد f % 2.
/// - قائد الفريق الثاني (بالدور) يفتح القبضات الفارغة ("طالعة") أو يأشر على وحدة ("بات").
///   * "بات" صح: فريقه ياخذ نقاط بعدد القبضات المسكّرة الباقية (غير هاي، وأقل شي 1)، والمحبس ينتقل إلهم.
///   * "طالعة" على قبضة بيها المحبس، أو "بات" على قبضة فارغة: الفريق المخبّي ياخذ النقاط ويخبّي مرة ثانية.
/// - مؤقت: 20 ثانية للتخبية و15 لكل حركة. إذا خلص: اختيار تلقائي.
/// - السيرفر بس يعرف مكان المحبس: [viewFor] يخفيه عن الفريق الثاني والمتفرجين.
/// - اللي يطلع قبضاته تختفي واللعبة تكمل. إذا فرغ فريق، الثاني يفوز.
class MuhaibesModel extends GameModel {
  MuhaibesModel({required super.players, required super.crazy, required super.seed})
      : out = List.filled(players, false),
        opened = List.filled(players * 2, false) {
    holding = rng.nextInt(2);
    _newRound();
  }

  MuhaibesModel.restore(super.j)
      : out = [for (final v in j['out'] as List) v == true],
        opened = [for (final v in j['op'] as List) v == true],
        holding = j['ht'] as int,
        hRot = [for (final v in j['hr'] as List) v as int],
        lRot = [for (final v in j['lr'] as List) v as int],
        phase = j['ph'] as String,
        ring = j['ring'] as int,
        hider = j['hider'] as int,
        leader = j['leader'] as int,
        aim = j['aim'] as int,
        deadline = (j['dl'] as num).toDouble(),
        teamScore = [for (final v in j['ts'] as List) v as int],
        winTeam = j['win'] as int,
        finished = j['fin'] == true,
        lastFist = j['lf'] as int,
        lastAct = j['la'] as String,
        lastTeam = j['lt'] as int,
        lastPts = j['lp'] as int,
        revealAt = (j['ra'] as num).toDouble(),
        super.restore();

  static const target = 15;
  static const hideTime = 20.0;
  static const moveTime = 15.0;
  static const revealTime = 3.5;

  @override
  String get id => 'muhaibes';

  /// بالدور، بس المؤقت يحتاج تكّات (قليلة تكفي)
  @override
  int get tickHz => 4;

  @override
  bool get teams => true;
  @override
  bool get secret => true;

  /// لاعب طلع نهائياً
  List<bool> out;

  /// القبضات المفتوحة (طالعة)
  List<bool> opened;

  /// الفريق اللي بيده المحبس (يخبّي)
  int holding = 0;

  /// دور المخبّي والقائد بكل فريق
  List<int> hRot = [0, 0], lRot = [0, 0];

  /// hide = المخبّي يختار، guess = القائد يدوّر، reveal = تنكشف النتيجة
  String phase = 'hide';

  /// قبضة المحبس (-1 = بعد ما تخبّى، أو مخفي عنك)
  int ring = -1;
  int hider = -1, leader = -1;

  /// القبضة اللي القائد يباوع عليها هسه (الكل يشوفها)
  int aim = -1;
  double deadline = 0;
  List<int> teamScore = [0, 0];
  int winTeam = -1;
  bool finished = false;

  /// آخر نتيجة (للكشف): القبضة، الحركة (open/bat)، الفريق اللي أخذ النقاط، وكم
  int lastFist = -1;
  String lastAct = '';
  int lastTeam = -1, lastPts = 0;
  double revealAt = 0;

  final _lastShake = <int, double>{};

  static int teamOf(int p) => p % 2;
  static int ownerOf(int fist) => fist ~/ 2;

  int get guessing => 1 - holding;
  double get timeLeft => (deadline - time).clamp(0, 99).toDouble();

  List<int> members(int team) => [
        for (var p = team; p < players; p += 2)
          if (!out[p]) p,
      ];

  /// قبضات الفريق المخبّي اللي بعدها مسكّرة
  List<int> get closedFists => [
        for (final p in members(holding))
          for (var h = 0; h < 2; h++)
            if (!opened[p * 2 + h]) p * 2 + h,
      ];

  bool _fistOfHolding(int f) => f >= 0 && f < players * 2 && teamOf(ownerOf(f)) == holding && !out[ownerOf(f)];

  @override
  bool get over => finished;

  /// أول لاعب بالفريق الفائز (حتى الأشياء القديمة اللي تتوقع لاعب واحد تشتغل)
  @override
  int get winner => winTeam;
  @override
  List<int> get winners => winTeam < 0 ? const [] : [for (var p = winTeam; p < players; p += 2) p];

  /// النقاط للفريقين
  @override
  List<int> get scores => teamScore;

  int _pick(List<int> list, List<int> rot, int team) {
    if (list.isEmpty) return -1;
    return list[rot[team] % list.length];
  }

  void _newRound() {
    opened = List.filled(players * 2, false);
    ring = -1;
    aim = -1;
    phase = 'hide';
    hider = _pick(members(holding), hRot, holding);
    leader = _pick(members(guessing), lRot, guessing);
    hRot[holding]++;
    lRot[guessing]++;
    deadline = time + hideTime;
    emit('round', {'h': hider, 'l': leader});
  }

  void _hide(int f) {
    ring = f;
    phase = 'guess';
    deadline = time + moveTime;
    emit('hidden');
  }

  /// نهاية الجولة: [team] أخذ [pts] نقطة
  void _resolve(int fist, String act, int team, int pts) {
    teamScore[team] += pts;
    lastFist = fist;
    lastAct = act;
    lastTeam = team;
    lastPts = pts;
    phase = 'reveal';
    revealAt = time;
    aim = -1;
    emit('reveal', {'f': fist, 'ring': ring, 'a': act, 'team': team, 'pts': pts});
  }

  int _pointsFor(int f) => [for (final x in closedFists) if (x != f) x].length.clamp(1, 99);

  @override
  void input(int player, Map<String, dynamic> d) {
    if (finished || player < 0 || player >= players || out[player]) return;
    final f = (d['f'] as num?)?.toInt() ?? -1;
    switch (d['a']) {
      case 'hide':
        if (phase != 'hide' || player != hider || !_fistOfHolding(f)) return;
        _hide(f);
      case 'aim':
        if (phase != 'guess' || player != leader) return;
        aim = closedFists.contains(f) ? f : -1;
      case 'open':
        if (phase != 'guess' || player != leader || !closedFists.contains(f)) return;
        _open(f);
      case 'bat':
        if (phase != 'guess' || player != leader || !closedFists.contains(f)) return;
        final pts = _pointsFor(f);
        if (f == ring) {
          _resolve(f, 'bat', guessing, pts);
        } else {
          _resolve(f, 'bat', holding, pts);
        }
      case 'shake':
        // الفريق المخبّي يحرّك قبضاته للتضليل
        if (phase == 'reveal' || teamOf(player) != holding || !_fistOfHolding(f) || opened[f]) return;
        if (time - (_lastShake[player] ?? -9) < 0.3) return;
        _lastShake[player] = time;
        emit('shake', {'f': f});
    }
  }

  void _open(int f) {
    if (f == ring) {
      _resolve(f, 'open', holding, _pointsFor(f));
      return;
    }
    opened[f] = true;
    if (aim == f) aim = -1;
    deadline = time + moveTime;
    emit('open', {'f': f});
  }

  @override
  void step(double dt) {
    if (finished) return;
    if (phase == 'hide' && time >= deadline) {
      final fists = closedFists;
      if (fists.isEmpty) return;
      _hide(fists[rng.nextInt(fists.length)]);
      emit('auto');
    } else if (phase == 'guess' && time >= deadline) {
      final fists = closedFists;
      if (fists.isEmpty) return;
      emit('auto');
      _open(fists[rng.nextInt(fists.length)]);
    } else if (phase == 'reveal' && time - revealAt >= revealTime) {
      final best = teamScore[0] >= teamScore[1] ? 0 : 1;
      if (teamScore[best] >= target) {
        _finish(best);
        return;
      }
      // اللي أخذ النقاط يصير المحبس بيده
      holding = lastTeam;
      _newRound();
    }
  }

  void _finish(int team) {
    winTeam = team;
    finished = true;
    phase = 'reveal';
    emit('win', {'team': team});
  }

  @override
  void forfeit(int player) {
    if (player < 0 || player >= players || out[player]) return;
    out[player] = true;
    emit('left', {'p': player});
    if (finished) return;
    for (final t in [0, 1]) {
      if (members(t).isEmpty) {
        _finish(1 - t);
        return;
      }
    }
    if (phase == 'hide' && player == hider) {
      hider = _pick(members(holding), hRot, holding);
      deadline = time + hideTime;
    } else if (phase == 'guess') {
      if (ring >= 0 && ownerOf(ring) == player) {
        // المحبس كان بيده: الجولة تنعاد بدون نقاط
        emit('void');
        _newRound();
        return;
      }
      if (player == leader) {
        leader = _pick(members(guessing), lRot, guessing);
        lRot[guessing]++;
        deadline = time + moveTime;
      }
      if (aim >= 0 && ownerOf(aim) == player) aim = -1;
    }
  }

  @override
  void again() {
    teamScore = [0, 0];
    winTeam = -1;
    finished = false;
    lastFist = -1;
    lastAct = '';
    lastTeam = -1;
    lastPts = 0;
    holding = rng.nextInt(2);
    _newRound();
  }

  /// الفريق الثاني والمتفرجين ما يشوفون مكان المحبس (إلا بالكشف)
  @override
  Map<String, dynamic> viewFor(int player) {
    final j = toJson();
    final mine = player >= 0 && player < players && teamOf(player) == holding;
    if (phase != 'reveal' && !mine) j['ring'] = -1;
    j['rng'] = 0; // حتى ما ينحزر الاختيار التلقائي
    return j;
  }

  @override
  Map<String, dynamic> save() => {
        'out': out,
        'op': opened,
        'ht': holding,
        'hr': hRot,
        'lr': lRot,
        'ph': phase,
        'ring': ring,
        'hider': hider,
        'leader': leader,
        'aim': aim,
        'dl': deadline,
        'ts': teamScore,
        'win': winTeam,
        'fin': finished,
        'lf': lastFist,
        'la': lastAct,
        'lt': lastTeam,
        'lp': lastPts,
        'ra': revealAt,
      };
}
