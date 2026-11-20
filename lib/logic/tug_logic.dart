import 'game_model.dart';

/// قواعد شد الحبل: لاعبين، كل ضغطة تسحب الحبل صوبك.
/// العد التنازلي جزء من القواعد حتى الكل يبدون بنفس اللحظة أونلاين.
class TugModel extends GameModel {
  TugModel({required super.players, required super.crazy, required super.seed});

  TugModel.restore(super.j)
      : pos = (j['pos'] as num).toDouble(),
        taps = [for (final v in j['taps'] as List) v as int],
        wins = [for (final v in j['wins'] as List) v as int],
        win = j['win'] as int,
        finished = j['fin'] == true,
        startAt = (j['start'] as num).toDouble(),
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

  bool get counting => time < startAt;

  @override
  bool get over => finished;
  @override
  int get winner => win;
  @override
  List<int> get scores => wins;

  @override
  void input(int player, Map<String, dynamic> d) {
    if (d['m'] != 'tap' || finished || counting || player < 0 || player > 1) return;
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
      };
}
