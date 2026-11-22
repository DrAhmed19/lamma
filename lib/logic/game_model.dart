// الأساس المشترك لكل الألعاب.
//
// قواعد كل لعبة تنكتب مرة وحدة هنا بـ Dart صافي (بدون Flutter):
//  - باللعب على نفس الجهاز: التطبيق يشغّلها بنفسه.
//  - بالأونلاين: السيرفر (Cloudflare) يشغّلها هو، وهو اللي يحسم النتيجة،
//    والتطبيقات بس تعرض الحالة وتدز الحركات.
// الكود نفسه ينبني لـ JavaScript للسيرفر (server/dart/main.dart).

import 'rng.dart';

abstract class GameModel {
  GameModel({required this.players, required this.crazy, required int seed}) : rng = Rng(seed);

  /// لاستعادة لعبة محفوظة
  GameModel.restore(Map<String, dynamic> j)
      : players = j['players'] as int,
        crazy = j['crazy'] == true,
        rng = (Rng(0)..state = j['rng'] as int) {
    time = (j['time'] as num).toDouble();
    tick = j['tick'] as int;
  }

  String get id;
  final int players;
  final bool crazy;
  final Rng rng;

  /// الوقت باللعبة بالثواني، ورقم التكّة
  double time = 0;
  int tick = 0;

  /// كم تكّة بالثانية. 0 = لعبة بالدور (ما تحتاج تكّات، تتغير بس بالحركات)
  int get tickHz => 0;

  /// على نفس الجهاز التكّات أكثر (الشاشة تنعرض بدون تنعيم). نفس القواعد.
  int get localHz => tickHz;

  /// خلصت المباراة؟ ومنو فاز (-1 = تعادل)
  bool get over;
  int get winner;
  List<int> get scores;

  /// كل الفائزين (ألعاب الفرق: الفريق كله). فاضي = تعادل.
  List<int> get winners => winner >= 0 ? [winner] : const [];
  bool isWinner(int player) => winners.contains(player);

  /// لعبة فرق؟ (النتيجة تنعرض للفرق مو للاعبين)
  bool get teams => false;

  /// تنحسب فوز وخسارة بإحصائيات اللاعب؟ (ألعاب الضحك مثل "منو بينا؟" لا)
  bool get scored => true;

  /// بيها معلومات مخفية؟ (مثل مكان المحبس). إذا إي السيرفر يدز لكل لاعب [viewFor] مالته.
  bool get secret => false;

  /// الحالة اللي يشوفها لاعب واحد (-1 = متفرج). لازم تبقى تنفع لـ restore.
  Map<String, dynamic> viewFor(int player) => toJson();

  /// حركة من لاعب (player = رقمه باللعبة 0..players-1)
  void input(int player, Map<String, dynamic> d);

  /// تقدّم اللعبة (للألعاب السريعة)
  void step(double dt) {}

  /// جولة جديدة بنفس المباراة (زر "مرة ثانية")
  void again();

  /// لاعب انقطع أو رجع. الألعاب ممكن تتصرف (مثلاً تكمل بدونه).
  void connection(int player, bool on) {}

  /// لاعب طلع نهائياً (طوّل وما رجع). بلعبتين: الثاني يفوز.
  void forfeit(int player) {}

  /// أحداث للمؤثرات (صوت، ريش، اهتزاز). تنسحب بعد كل تكّة وتنعرض بالتطبيق.
  final List<Map<String, dynamic>> events = [];
  void emit(String e, [Map<String, dynamic>? d]) => events.add({'e': e, ...?d});

  List<Map<String, dynamic>> drainEvents() {
    final out = List.of(events);
    events.clear();
    return out;
  }

  /// يمشي اللعبة تكّة وحدة
  void advance(double dt) {
    time += dt;
    tick++;
    step(dt);
  }

  /// الحالة الكاملة (تكفي حتى ترجع اللعبة بالضبط)
  Map<String, dynamic> toJson() => {
        'id': id,
        'players': players,
        'crazy': crazy,
        'rng': rng.state,
        'time': time,
        'tick': tick,
        ...save(),
      };

  /// حالة اللعبة الخاصة
  Map<String, dynamic> save();
}
