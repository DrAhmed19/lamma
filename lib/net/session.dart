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
      } else if (me >= 0 && !m.scored) {
        Profile.I.recordGame(m.id, online: true);
      } else if (me >= 0) {
        // الخصوم بالاسم (لإحصائية صورة النتيجة: "فاز على فلان 5 مرات متتالية")
        // ألعاب الفرق: الفائزين ممكن أكثر من واحد، وزميلي ما ينحسب خصم
        final winners = m.winners;
        final iWon = m.isWinner(me);
        String? nm(int p) => nameOf(p).trim().isEmpty ? null : nameOf(p);
        Profile.I.recordGame(
          m.id,
          won: iWon,
          online: true,
          beat: iWon ? [for (var p = 0; p < m.players; p++) if (!m.isWinner(p) && nm(p) != null) nm(p)!] : const [],
          lostTo: !iWon && winners.length == 1 ? nm(winners.first) : null,
          drew: winners.isEmpty ? [for (var p = 0; p < m.players; p++) if (p != me && nm(p) != null) nm(p)!] : const [],
        );
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

  // العرض أونلاين (للألعاب السريعة): نخزن الحالات اللي توصل بمخزن صغير ونعرض
  // متأخرين شوية (delay) عن آخر حالة، ونعتمد على وقت السيرفر (model.time) مو وقت
  // الوصول. هيج تأخر الشبكة المتذبذب ما يسبب تقطيع ووقوف ثم قفزة.
  final List<_Snap<M>> _buf = [];
  M? _model, _prev;
  double _blend = 1;
  double _offset = double.nan; // ساعتنا - وقت السيرفر (أقل قيمة = أسرع وصول)
  double _late = 0.02; // متوسط تأخر الحزم عن أسرعها (التذبذب)
  double _gap = 1 / 30; // الفرق بين حالتين بوقت السيرفر
  bool _realtime = false;
  bool _silent = false;
  final List<Map<String, dynamic>> _events = [];

  bool get ready => _model != null;

  @override
  M get model => _model!;
  @override
  M? get prev => _prev;

  @override
  double get blend => _blend;

  void _apply(NetState st, {bool firstTime = false}) {
    final m = st.model;
    if (m is! M) return;
    _quiet = 0;
    _quietLimit = 3;
    _realtime = m.tickHz > 0;
    final ev = firstTime ? const <Map<String, dynamic>>[] : st.events;
    if (!_realtime) {
      // لعبة بالدور: نعرض آخر حالة فوراً
      _buf.clear();
      _prev = _model;
      _model = m;
      _blend = 1;
      _events.addAll(ev);
      watchResult(silent: firstTime);
      return;
    }
    final t = m.time;
    // جولة جديدة (الوقت رجع لورا): نبدي من جديد
    if (_buf.isNotEmpty && t < _buf.last.t - 1e-6) {
      for (final s in _buf) {
        s.fire(_events);
      }
      _buf.clear();
      _offset = double.nan;
    }
    if (_buf.isNotEmpty && (t - _buf.last.t).abs() < 1e-6) {
      // نفس التكّة وصلت مرتين: نبدّل الحالة ونجمع الأحداث
      final old = _buf.removeLast();
      _buf.add(_Snap(m, t, [...old.ev, ...ev]));
    } else {
      if (_buf.isNotEmpty) {
        final g = t - _buf.last.t;
        if (g > 0 && g < 0.5) _gap = _gap * 0.9 + g * 0.1;
      }
      _buf.add(_Snap(m, t, ev));
    }
    final o = st.at - t;
    if (_offset.isNaN || o < _offset) {
      _offset = o;
    } else {
      _offset += (o - _offset) * 0.01; // يلحق ببطء إذا الطريق تبدّل وصار أبطأ
    }
    _late = _late * 0.9 + (o - _offset) * 0.1;
    while (_buf.length > 40) {
      _buf.removeAt(0).fire(_events);
    }
    if (_model == null) {
      // أول حالة: نعرضها فوراً حتى اللعبة تفتح بدون انتظار
      _model = m;
      _prev = null;
      _blend = 1;
      _silent = firstTime;
      watchResult(silent: firstTime);
    }
  }

  @override
  bool get online => true;
  @override
  int get me => room.me;
  @override
  String nameOf(int player) => room.nameOf(player);
  @override
  bool isOn(int player) => room.isOn(player);

  @override
  void input(int player, Map<String, dynamic> d) => room.input(d);

  @override
  void again() => room.again();

  // ما وصلت حالة من فترة (اللعبة على "جارٍ الاتصال"، أو لعبة سريعة وقفت): نرجع نتصل
  double _quiet = 0, _quietLimit = 3;

  void _watchQuiet(double dt) {
    final waiting = !ready || (_realtime && !model.over);
    if (!waiting) {
      _quiet = 0;
      _quietLimit = 3;
      return;
    }
    _quiet += math.min(dt, 0.1);
    if (_quiet >= _quietLimit) {
      _quiet = 0;
      _quietLimit = math.min(12, _quietLimit * 1.8); // ما نكرر بسرعة إذا ما نفع
      room.wake(force: true);
    }
  }

  @override
  void update(double dt) {
    _watchQuiet(dt);
    if (!_realtime || _buf.isEmpty || _offset.isNaN) return;
    final delay = (_gap + 2.5 * _late).clamp(0.05, 0.25);
    var rt = netNow - _offset - delay;
    // متأخرين هواي (التطبيق نام أو تعلّق): نقفز لآخر حالة
    if (_buf.last.t - rt > 0.6) {
      _offset = netNow - delay - _buf.last.t;
      rt = _buf.last.t;
    }
    for (final s in _buf) {
      if (s.t > rt) break;
      s.fire(_events);
    }
    while (_buf.length >= 2 && _buf[1].t <= rt) {
      _buf.removeAt(0);
    }
    final a = _buf[0];
    if (_buf.length == 1 || rt <= a.t) {
      _prev = null;
      _model = a.m;
      _blend = 1;
    } else {
      final b = _buf[1];
      _prev = a.m;
      _model = b.m;
      _blend = ((rt - a.t) / (b.t - a.t)).clamp(0.0, 1.0);
    }
    watchResult(silent: _silent);
    _silent = false;
  }

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

class _Snap<M> {
  _Snap(this.m, this.t, this.ev);
  final M m;
  final double t;
  final List<Map<String, dynamic>> ev;
  bool _fired = false;

  void fire(List<Map<String, dynamic>> out) {
    if (_fired) return;
    _fired = true;
    out.addAll(ev);
  }
}
