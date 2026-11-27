import 'dart:math' as math;

import 'game_model.dart';
import 'quiz_bank.dart';

/// قواعد "سؤال وجواب": 2-4 لاعبين، 10 أسئلة.
/// كل سؤال 12 ثانية. الجواب الصحيح بنقطة، وأسرع جواب صحيح ياخذ نقطة زيادة.
/// [level] 2 (صعب): الجواب الغلط ينقص نقطة. المستوى يحدد قوة الكمبيوتر أيضاً.
class QuizModel extends GameModel {
  QuizModel({required super.players, required super.crazy, required super.seed, int level = 1})
      : level = level.clamp(0, 2),
        score = List.filled(players, 0),
        answers = List.filled(players, -1),
        answeredAt = List.filled(players, 0),
        out = List.filled(players, false) {
    _pick();
  }

  QuizModel.restore(super.j)
      : score = [for (final v in j['score'] as List) v as int],
        answers = [for (final v in j['ans'] as List) v as int],
        answeredAt = [for (final v in j['at'] as List) (v as num).toDouble()],
        out = [for (final v in j['out'] as List) v == true],
        qs = [for (final v in j['qs'] as List) v as int],
        qi = j['qi'] as int,
        reveal = j['rev'] == true,
        askedAt = (j['asked'] as num).toDouble(),
        revealAt = (j['revAt'] as num).toDouble(),
        fastest = j['fast'] as int,
        started = j['started'] == true,
        startAt = (j['start'] as num).toDouble(),
        win = j['win'] as int,
        finished = j['fin'] == true,
        level = (j['lv'] as int?) ?? 1,
        super.restore();

  static const questions = 10;
  static const askTime = 12.0;
  static const revealTime = 3.2;
  static const countdown = 2.6;

  @override
  String get id => 'quiz';
  @override
  int get tickHz => 10;
  @override
  int get localHz => 20;

  final int level;
  List<int> score, answers;
  List<double> answeredAt;
  List<bool> out;
  List<int> qs = [];
  int qi = 0;
  bool reveal = false;
  double askedAt = 0, revealAt = 0;

  /// أسرع واحد جاوب صح بهالسؤال (-1 = ماكو)
  int fastest = -1;
  bool started = false;
  double startAt = countdown;
  int win = -1;
  bool finished = false;

  bool get counting => !started;
  @override
  bool get over => finished;
  @override
  int get winner => win;
  @override
  List<int> get scores => score;

  (String, List<String>, int) get current => quizBank[qs[qi]];
  double get timeLeft => math.max(0, askTime - (time - askedAt));

  void _pick() {
    final idx = List.generate(quizBank.length, (i) => i);
    for (var i = idx.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final t = idx[i];
      idx[i] = idx[j];
      idx[j] = t;
    }
    qs = idx.take(questions).toList();
    qi = 0;
  }

  void _ask() {
    answers = List.filled(players, -1);
    answeredAt = List.filled(players, 0);
    reveal = false;
    fastest = -1;
    askedAt = time;
    emit('q', {'i': qi});
  }

  void _reveal() {
    reveal = true;
    revealAt = time;
    final c = current.$3;
    var best = double.infinity;
    for (var p = 0; p < players; p++) {
      if (answers[p] != c && answers[p] >= 0 && level == 2 && score[p] > 0) score[p]--;
      if (answers[p] == c) {
        score[p]++;
        if (answeredAt[p] < best) {
          best = answeredAt[p];
          fastest = p;
        }
      }
    }
    if (fastest >= 0) score[fastest]++;
    emit('reveal', {'c': c, 'fast': fastest});
  }

  void _finish(int w) {
    win = w;
    finished = true;
    emit('win', {'p': w});
  }

  bool get _allAnswered {
    for (var p = 0; p < players; p++) {
      if (!out[p] && answers[p] < 0) return false;
    }
    return true;
  }

  @override
  void step(double dt) {
    if (finished) return;
    if (!started) {
      if (time >= startAt) {
        started = true;
        _ask();
      }
      return;
    }
    if (!reveal) {
      if (time - askedAt >= askTime || _allAnswered) _reveal();
    } else if (time - revealAt >= revealTime) {
      if (qi >= qs.length - 1) {
        final best = score.reduce(math.max);
        final tops = [for (var i = 0; i < players; i++) if (score[i] == best && !out[i]) i];
        _finish(tops.length == 1 ? tops.first : -1);
      } else {
        qi++;
        _ask();
      }
    }
  }

  @override
  void input(int player, Map<String, dynamic> d) {
    if (d['m'] != 'ans' || !started || finished || reveal || player < 0 || player >= players) return;
    final a = d['a'];
    if (a is! int || a < 0 || a > 3 || out[player] || answers[player] >= 0) return;
    answers[player] = a;
    answeredAt[player] = time - askedAt;
    emit('ans', {'p': player});
  }

  @override
  void forfeit(int player) {
    if (finished || player < 0 || player >= players || out[player]) return;
    out[player] = true;
    final alive = [for (var i = 0; i < players; i++) if (!out[i]) i];
    if (alive.length == 1) _finish(alive.first);
  }

  @override
  void again() {
    score = List.filled(players, 0);
    answers = List.filled(players, -1);
    answeredAt = List.filled(players, 0);
    reveal = false;
    fastest = -1;
    started = false;
    finished = false;
    win = -1;
    startAt = time + countdown;
    _pick();
    emit('again');
  }

  @override
  Map<String, dynamic> save() => {
        'score': score,
        'ans': answers,
        'at': answeredAt,
        'out': out,
        'qs': qs,
        'qi': qi,
        'rev': reveal,
        'asked': askedAt,
        'revAt': revealAt,
        'fast': fastest,
        'started': started,
        'start': startAt,
        'win': win,
        'fin': finished,
        'lv': level,
      };
}
