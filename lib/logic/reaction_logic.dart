import 'dart:math' as math;

import 'game_model.dart';

/// قواعد أسرع إصبع: 2-4 لاعبين. الإشارة (الانتظار، الخدعة، الأخضر) كلها يقررها الموديل،
/// واللاعب بس يدز "tap". كل شي بالوقت حتى يشتغل بالسيرفر نفسه.
class ReactionModel extends GameModel {
  ReactionModel({required super.players, required super.crazy, required super.seed})
      : score = List.filled(players, 0),
        fouled = List.filled(players, false),
        out = List.filled(players, false);

  ReactionModel.restore(super.j)
      : score = [for (final v in j['score'] as List) v as int],
        fouled = [for (final v in j['fouled'] as List) v == true],
        out = [for (final v in j['out'] as List) v == true],
        rs = j['rs'] as int,
        started = j['started'] == true,
        startAt = (j['start'] as num).toDouble(),
        goAt = (j['goAt'] as num).toDouble(),
        nextAt = (j['nextAt'] as num).toDouble(),
        decoyAt = (j['decoyAt'] as num).toDouble(),
        decoyEnd = (j['decoyEnd'] as num).toDouble(),
        roundEndAt = (j['roundEndAt'] as num).toDouble(),
        roundWinner = j['rw'] as int,
        reactionMs = j['ms'] as int,
        wonByFoul = j['wbf'] == true,
        win = j['win'] as int,
        finished = j['fin'] == true,
        super.restore();

  static const target = 5;
  static const countdown = 2.6;

  /// حالة الإشارة
  static const waiting = 0, decoy = 1, go = 2, roundEnd = 3;

  @override
  String get id => 'reaction';

  @override
  int get tickHz => 30;
  @override
  int get localHz => 60;

  List<int> score;
  List<bool> fouled;

  /// لاعب طلع من المباراة
  List<bool> out;
  int rs = waiting;
  bool started = false;
  double startAt = countdown;
  double goAt = 0, nextAt = 0, decoyAt = -1, decoyEnd = 0, roundEndAt = 0;
  int roundWinner = -1;
  int reactionMs = 0;
  bool wonByFoul = false;
  int win = -1;
  bool finished = false;

  bool get counting => !started;

  @override
  bool get over => finished;
  @override
  int get winner => win;
  @override
  List<int> get scores => score;

  List<int> get _alive => [for (var i = 0; i < players; i++) if (!out[i]) i];
  List<int> get _free => [for (var i = 0; i < players; i++) if (!out[i] && !fouled[i]) i];

  void _startRound() {
    fouled = [for (var i = 0; i < players; i++) out[i]];
    roundWinner = -1;
    wonByFoul = false;
    rs = waiting;
    final wait = 1.6 + rng.next() * 2.8;
    nextAt = time + wait;
    decoyAt = rng.next() < 0.35 ? time + wait * (0.35 + rng.next() * 0.3) : -1;
  }

  void _endRound(int p, {bool byFoul = false}) {
    roundWinner = p;
    wonByFoul = byFoul;
    score[p]++;
    rs = roundEnd;
    roundEndAt = time + 1.5;
    emit('round', {'p': p, 'foul': byFoul, 'ms': reactionMs});
  }

  void _finish(int w) {
    win = w;
    finished = true;
    emit('win', {'p': w});
  }

  @override
  void step(double dt) {
    if (finished) return;
    if (!started) {
      if (time >= startAt) {
        started = true;
        _startRound();
      }
      return;
    }
    switch (rs) {
      case waiting:
        if (decoyAt > 0 && time >= decoyAt) {
          rs = decoy;
          decoyEnd = time + 0.5;
          decoyAt = -1;
          emit('decoy');
        } else if (time >= nextAt) {
          rs = go;
          goAt = time;
          emit('go');
        }
      case decoy:
        if (time >= decoyEnd) {
          rs = waiting;
          if (time >= nextAt) nextAt = time + 0.6 + rng.next();
        }
      case roundEnd:
        if (time >= roundEndAt) {
          final best = score.reduce(math.max);
          if (best >= target) {
            _finish(score.indexOf(best));
          } else {
            _startRound();
          }
        }
    }
  }

  @override
  void input(int player, Map<String, dynamic> d) {
    if (d['m'] != 'tap' || !started || finished || player < 0 || player >= players) return;
    if (out[player] || fouled[player]) return;
    if (rs == go) {
      reactionMs = ((time - goAt) * 1000).round();
      emit('tap', {'p': player, 'ms': reactionMs});
      _endRound(player);
    } else if (rs == waiting || rs == decoy) {
      fouled[player] = true;
      emit('foul', {'p': player});
      final left = _free;
      if (left.length == 1) _endRound(left.first, byFoul: true);
    }
  }

  @override
  void forfeit(int player) {
    if (finished || player < 0 || player >= players || out[player]) return;
    out[player] = true;
    fouled[player] = true;
    final alive = _alive;
    if (alive.length == 1) {
      _finish(alive.first);
      return;
    }
    if (started && (rs == waiting || rs == decoy)) {
      final left = _free;
      if (left.length == 1) {
        _endRound(left.first, byFoul: true);
      } else if (left.isEmpty) {
        _startRound();
      }
    }
  }

  @override
  void again() {
    score = List.filled(players, 0);
    fouled = [for (var i = 0; i < players; i++) out[i]];
    rs = waiting;
    started = false;
    startAt = time + countdown;
    goAt = 0;
    nextAt = 0;
    decoyAt = -1;
    decoyEnd = 0;
    roundEndAt = 0;
    roundWinner = -1;
    reactionMs = 0;
    wonByFoul = false;
    win = -1;
    finished = false;
    emit('again');
  }

  @override
  Map<String, dynamic> save() => {
        'score': score,
        'fouled': fouled,
        'out': out,
        'rs': rs,
        'started': started,
        'start': startAt,
        'goAt': goAt,
        'nextAt': nextAt,
        'decoyAt': decoyAt,
        'decoyEnd': decoyEnd,
        'roundEndAt': roundEndAt,
        'rw': roundWinner,
        'ms': reactionMs,
        'wbf': wonByFoul,
        'win': win,
        'fin': finished,
      };
}
