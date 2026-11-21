import 'dart:async';
import 'dart:math' as math;

import '../core/profile.dart';
import '../logic/game_model.dart';
import 'room.dart';

/// الواجهة الوحدة اللي تشوفها كل لعبة، سواء على نفس الجهاز أو أونلاين.
/// اللعبة (الرسم واللمس) تقرا من [model] وترسل حركاتها بـ [input]،
/// وما تحتاج تعرف منو اللي يدير القواعد.
abstract class Session<M extends GameModel> {
  /// الحالة الحالية
  M get model;

  /// الحالة اللي قبلها (أونلاين) حتى ننعّم الحركة بيناتهم، و[blend] من 0 لـ 1
  M? get prev;
  double get blend;

  bool get online;

  /// رقمي باللعبة. على نفس الجهاز = -1 (كل اللاعبين على نفس الشاشة)
  int get me;

  String nameOf(int player);

  /// متصل ويلعب؟ (على نفس الجهاز دائماً إي)
  bool isOn(int player);

  /// حركة. على نفس الجهاز لازم تحدد اللاعب، أونلاين السيرفر يعرف منو انت.
  void input(int player, Map<String, dynamic> d);

  void again();

  /// يتنادى كل إطار
  void update(double dt);

  /// أحداث المؤثرات اللي صارت من آخر مرة
  List<Map<String, dynamic>> takeEvents();

  void dispose() {}

  /// قيمة بين الحالة السابقة والحالية (للحركة الناعمة أونلاين)
  bool _wasOver = false;

  /// لمّن تخلص مباراة نسجّلها بإحصائيات اللاعب
  void watchResult({bool silent = false}) {
    final m = model;
    if (m.over && !_wasOver && !silent) {
      if (!online) {
        Profile.I.recordGame(m.id);
      } else if (me >= 0) {
        Profile.I.recordGame(m.id, won: m.winner == me, online: true);
      }
    }
    _wasOver = m.over;
  }

  double lerp(double Function(M m) f) {
    final p = prev;
    if (p == null) return f(model);
    final a = f(p), b = f(model);
    return a + (b - a) * blend;
  }
}

/// على نفس الجهاز: التطبيق يشغّل القواعد بنفسه
class LocalSession<M extends GameModel> extends Session<M> {
  LocalSession(this.model);

  @override
  final M model;
  double _acc = 0;

  @override
  M? get prev => null;
  @override
  double get blend => 1;
  @override
  bool get online => false;
  @override
  int get me => -1;
  @override
  String nameOf(int player) => '';
  @override
  bool isOn(int player) => true;

  @override
  void input(int player, Map<String, dynamic> d) {
    model.input(player, d);
    watchResult();
  }

  @override
  void again() => model.again();

  @override
  void update(double dt) {
    final hz = model.localHz;
    if (hz <= 0) return;
    // تكّات ثابتة (نفس السيرفر) حتى اللعب يصير نفسه بالضبط
    _acc += math.min(dt, 0.1);
    final step = 1 / hz;
    while (_acc >= step) {
      model.advance(step);
      _acc -= step;
    }
    watchResult();
  }

  @override
  List<Map<String, dynamic>> takeEvents() => model.drainEvents();
}

/// أونلاين: السيرفر يدير القواعد، وهنا بس نعرض آخر حالة وصلت
class OnlineSession<M extends GameModel> extends Session<M> {
  OnlineSession(this.room) {
    final st = room.state;
    if (st != null) _apply(st, firstTime: true);
    _sub = room.states.listen(_apply);
  }

  final RoomConn room;
  late StreamSubscription<NetState> _sub;
  M? _model, _prev;
  double _recvAt = 0, _interval = 0.05;
  final List<Map<String, dynamic>> _events = [];

  bool get ready => _model != null;

  @override
  M get model => _model!;
  @override
  M? get prev => _prev;

  @override
  double get blend {
    if (_prev == null) return 1;
    return ((netNow - _recvAt) / _interval).clamp(0.0, 1.0);
  }

  @override
  bool get online => true;
  @override
  int get me => room.me;
  @override
  String nameOf(int player) => room.nameOf(player);
  @override
  bool isOn(int player) => room.isOn(player);

  void _apply(NetState st, {bool firstTime = false}) {
    final m = st.model;
    if (m is! M) return;
    if (_model != null) {
      final gap = st.at - _recvAt;
      if (gap > 0 && gap < 0.5) _interval = _interval * 0.8 + gap * 0.2;
    }
    _prev = _model;
    _model = m;
    _recvAt = st.at;
    if (!firstTime) _events.addAll(st.events);
    watchResult(silent: firstTime);
  }

  @override
  void input(int player, Map<String, dynamic> d) => room.input(d);

  @override
  void again() => room.again();

  @override
  void update(double dt) {}

  @override
  List<Map<String, dynamic>> takeEvents() {
    final out = List.of(_events);
    _events.clear();
    return out;
  }

  @override
  void dispose() {
    _sub.cancel();
    // طلعت من شاشة اللعبة وهي بعدها شغالة = انسحبت، والباقين يكملون
    if (room.playing && ready && !model.over) room.quit();
  }
}
