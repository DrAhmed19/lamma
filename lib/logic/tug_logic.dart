import 'game_model.dart';

/// قواعد شد الحبل: لاعبين، كل ضغطة تسحب الحبل صوبك.
/// العد التنازلي جزء من القواعد حتى الكل يبدون بنفس اللحظة أونلاين.
/// [level]: 0 سهل (اضغط بسرعة)، 1 متوسط (لحظات «توقف!»: اللي يضغط وقتها يرجع لورا)،
/// 2 صعب (توقف أكثر وأسرع ومفاجئ).
class TugModel extends GameModel {
  TugModel({required super.players, required super.crazy, required super.seed, int level = 0}) : level = level.clamp(0, 2);

  TugModel.restore(super.j)
      : pos = (j['pos'] as num).toDouble(),
        taps = [for (final v in j['taps'] as List) v as int],
        wins = [for (final v in j['wins'] as List) v as int],
        win = j['win'] as int,
        finished = j['fin'] == true,
        startAt = (j['start'] as num).toDouble(),
        level = (j['lv'] as int?) ?? 0,
        stopAt = (j['stopAt'] as num?)?.toDouble() ?? -1,
        stopEnd = (j['stopEnd'] as num?)?.toDouble() ?? -1,
        super.restore();

  /// مدة العد التنازلي (نفس Countdown بالواجهة)
  static const countdown = 2.6;
  static const stepSize = 0.045;

  @override
  String get id => 'tug';

  @override
  int get tickHz => 20;

  /// -1..1، الموجب لصالح اللاعب 0
  double pos = 0;
  List<int> taps = [0, 0];
  List<int> wins = [0, 0];
  int win = -1;
  bool finished = false;
  double startAt = countdown;

  final int level;

  /// موعد «توقف!» الجاي ونهاية الحالي (المتوسط والصعب)
  double stopAt = -1, stopEnd = -1;
  bool get stopping => level > 0 && time < stopEnd && time >= stopEnd - (level == 2 ? 0.7 : 0.9);

  bool get counting => time < startAt;

  void _planStop() {
    final gap = level == 2 ? 1.6 + rng.next() * 2.2 : 2.6 + rng.next() * 3.0;
    stopAt = time + gap;
    stopEnd = -1;
  }

  @override
  void step(double dt) {
    if (level == 0 || finished || counting) return;
    if (stopAt < 0 && stopEnd < 0) _planStop();
    if (stopEnd < 0 && stopAt >= 0 && time >= stopAt) {
      stopEnd = time + (level == 2 ? 0.7 : 0.9);
      stopAt = -1;
      emit('stop');
    } else if (stopEnd >= 0 && time >= stopEnd) {
      _planStop();
    }
  }

  @override
  bool get over => finished;
  @override
  int get winner => win;
  @override
  List<int> get scores => wins;

  @override
  void input(int player, Map<String, dynamic> d) {
    if (d['m'] != 'tap' || finished || counting || player < 0 || player > 1) return;
    if (stopping) {
      // ضغطت وقت «توقف!»: الحبل يرجع لورا
      pos += player == 0 ? -stepSize * 2 : stepSize * 2;
      pos = pos.clamp(-1.0, 1.0);
      emit('foul', {'p': player});
      return;
    }
    taps[player]++;
    pos += player == 0 ? stepSize : -stepSize;
    emit('tap', {'p': player});
    if (pos.abs() >= 1) {
      pos = pos.sign;
      win = pos > 0 ? 0 : 1;
      wins[win]++;
      finished = true;
      emit('win', {'p': win});
    }
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
    pos = 0;
    taps = [0, 0];
    win = -1;
    finished = false;
    startAt = time + countdown;
    stopAt = -1;
    stopEnd = -1;
    emit('again');
  }

  @override
  Map<String, dynamic> save() => {
        'pos': pos,
        'taps': taps,
        'wins': wins,
        'win': win,
        'fin': finished,
        'start': startAt,
        'lv': level,
        'stopAt': stopAt,
        'stopEnd': stopEnd,
      };
}
