import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/loop.dart';
import '../core/profile.dart';
import '../core/sfx.dart';
import '../logic/domino_bot.dart';
import '../logic/domino_logic.dart';
import '../net/room.dart';
import 'domino_board.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/setup.dart' show kLevelColors, kLevelNames;
import '../ui/art.dart';
import '../ui/theme.dart';

/// الدومينو: 2 أو 4 لاعبين. القواعد بـ DominoModel (نفسها بالسيرفر، والسيرفر يخفي قطع الخصم).
/// على نفس الجهاز: "مرّر التلفون" ويا شاشة إخفاء بين الأدوار.
/// للاختبارات: موديل آخر دومينو انفتح
@visibleForTesting
DominoModel Function()? debugDominoModel;

class DominoGame extends StatefulWidget {
  const DominoGame({super.key, this.players = 2, this.long = false, this.room, this.level, this.bots});
  final int players;

  /// الهدف 100 بدل 50 (القديم، بدون مستويات)
  final bool long;
  final RoomConn? room;

  /// المستوى (0 سهل، 1 متوسط، 2 صعب). null = القديم.
  final int? level;

  /// المقاعد اللي يلعبها الكمبيوتر (على هذا الجهاز)
  final List<bool>? bots;

  @override
  State<DominoGame> createState() => _DominoState();
}

const _felt = Color(0xFF0E4D3A);
const _gold = Color(0xFFFFD34D);

class _DominoState extends LoopState<DominoGame> {
  late final Session<DominoModel> session = widget.room != null
      ? OnlineSession<DominoModel>(widget.room!)
      : LocalSession(DominoModel(players: widget.players, crazy: widget.long, seed: DateTime.now().microsecondsSinceEpoch, level: widget.level ?? -1));

  /// أونلاين: حركتي تنعرض فوراً (نسخة متوقعة) لحد ما توصل من السيرفر
  DominoModel? _pred;
  int _predTile = -1;
  double _predAt = 0;

  /// أحجار انعرضت حركتها مسبقاً (حتى ما تنعاد لمّن توصل من السيرفر)
  final _predShown = <int>{};

  DominoModel get m {
    final real = session.model;
    final p = _pred;
    if (p != null) {
      final me = session.me;
      if (time - _predAt < 1.5 && me >= 0 && me < real.hands.length && real.hands[me].contains(_predTile)) return p;
      _pred = null;
    }
    return real;
  }

  @override
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;
  bool get online => session.online;

  // ------------------------------------------------------------ الكمبيوتر والأشخاص (على هذا الجهاز)

  bool isBot(int p) => online ? (widget.room?.isBot(p) ?? false) : widget.bots != null && p >= 0 && p < widget.bots!.length && widget.bots![p];
  late final List<int> humans = [
    for (var p = 0; p < widget.players; p++)
      if (!isBot(p)) p
  ];

  /// أكثر من شخص على نفس التلفون؟ (يحتاجون "مرّر التلفون")
  bool get multiHuman => !online && humans.length > 1;

  /// آخر شخص كان دوره (نعرض يده وقت دور الكمبيوتر)
  int _lastHuman = -1;

  /// اللاعب اللي نعرض يده تحت: أونلاين آني، على نفس الجهاز الشخص اللي دوره (أو آخر واحد)
  int get vp {
    if (online) return session.me;
    if (!isBot(m.turn) && (multiHuman || humans.isEmpty)) return m.turn;
    if (_lastHuman >= 0) return _lastHuman;
    return humans.isEmpty ? m.turn : humans.first;
  }

  /// قوة الكمبيوتر حسب المستوى (سهل = 1، متوسط = 3، صعب = 4 "الوحش")
  int get botLevel => switch (widget.level) { 0 => 1, 1 => 3, 2 => 4, _ => 2 };
  final _botRng = math.Random();
  double _botAt = -1;
  int _botTurn = -1;

  /// الكمبيوتر اللي يفكّر هسة (-1 = ماكو)
  int thinking = -1;

  /// على نفس الجهاز: آخر لاعب ضغط "أنا جاهز" (حتى ما يشوف قطع غيره)
  int _readyFor = -1;

  /// (الشاشة تتغطى بس بعد ما تنزل القطعة وتطلع نقاطها، حتى اللاعب يشوف حركته)
  bool get hidden => multiHuman && m.phase == 'play' && !m.over && !isBot(m.turn) && _readyFor != m.turn;
  bool get covered => hidden && flyTile < 0 && time - landAt > 0.6 && floats.isEmpty;

  int selected = -1;

  /// الحجر اللي ما ينفع ينهز (العدّاد يعيد الحركة)
  int shakeTile = -1, shakeN = 0;
  int _lastTapTile = -1;
  double _lastTapAt = -10;

  /// السحب بالإصبع (بدون setState كل حركة، حتى ما يتقطع)
  final ValueNotifier<_Drag?> drag = ValueNotifier(null);
  final _rootKey = GlobalKey(), _boardKey = GlobalKey();
  final _tileKeys = <int, GlobalKey>{};

  /// منين طلعت قطعتي (إحداثيات الطاولة)، حتى تطير من مكانها الحقيقي
  ({int t, Offset from, bool vertical})? _launch;
  Offset? flyFromPt;
  bool flyVertical = true;
  double endAt = 0;
  bool showOver = false;
  String _sig = '';
  int _lastTick = -1;

  /// يتغير لمّن السلسلة تتغير (حتى الطاولة ما تنرسم كل إطار)
  final ValueNotifier<int> boardVer = ValueNotifier(0);

  /// تخطيط الطاولة، والكاميرا الحالية (تمشي بنعومة للهدف لمّن السلسلة تطول وتصغر)
  BoardLayout? lay;
  BoardCam? cam, camTarget;
  String _layKey = '';
  Size _boardSize = Size.zero;

  void ensureLayout(Size size) {
    final key = '${m.chain}|${m.up}|${m.dn}|${size.width.round()}x${size.height.round()}';
    if (key == _layKey && lay != null) return;
    final resized = size != _boardSize;
    _layKey = key;
    _boardSize = size;
    final (l, c) = fitBoard(m, size, 34);
    lay = l;
    camTarget = c;
    // أول مرة أو تغيّر حجم الشاشة أو جولة جديدة: بدون حركة
    if (cam == null || resized || m.chainLen <= 1) cam = c;
  }

  /// قطعة نازلة على الطاولة (حركة من مكان اللاعب لمكانها بالسلسلة)
  int flyTile = -1, flyFrom = 0;
  double flyAt = -10;
  static const flyDur = 0.46;

  /// قطعتي أسرع (قريبة ومن إيدي)
  static const flyDurMine = 0.3;
  double get flyLen => flyFromPt != null ? flyDurMine : flyDur;

  /// آخر قطعة نزلت (لموجة النزول)
  int landT = -1;
  double landAt = -10;

  /// أرقام النقاط العائمة (الخمسات)
  final floats = <({int t, int pts, double at})>[];
  static const floatDur = 1.6;

  /// فقاعات "مرّر" و"سحب" فوق اللاعبين
  final bubbles = <({int p, String text, double at})>[];
  static const bubbleDur = 1.8;

  /// مكان اللاعب بالشاشة: 0 = تحت (آني)، وبالأربعة 1 = يسار، 2 = فوق (شريكي)، 3 = يمين. باثنين: 1 = فوق.
  int rel(int p) {
    final base = vp < 0 ? 0 : vp;
    return (p - base + m.players) % m.players;
  }

  /// فوق؟ (الخصم باثنين أو الشريك بأربعة)
  bool isTop(int r) => m.players == 2 ? r == 1 : r == 2;

  @override
  void initState() {
    super.initState();
    debugDominoModel = () => m;
    Sfx.preload(const ['clack', 'pop', 'tick', 'gold', 'freeze', 'win', 'whoosh']);
  }

  @override
  void dispose() {
    boardVer.dispose();
    drag.dispose();
    session.dispose();
    super.dispose();
  }

  @override
  void restart() {
    if (online && !m.over) return;
    _readyFor = -1;
    _botAt = -1;
    thinking = -1;
    session.again();
  }

  /// وكت بداية نتيجة الجولة عندي (لشريط "لا توجد حركات" والنافذة)
  double roundShownAt = -10;

  /// الكمبيوتر: يفكّر شوية (فقاعة) وبعدين يلعب. ويضغط "الجولة التالية" وحده.
  void _driveBots() {
    if (online) {
      // أونلاين: السيرفر يلعب الكمبيوتر، وهنا بس فقاعة "يفكّر"
      final t = ready && m.phase == 'play' && !m.over && isBot(m.turn) && flyTile < 0 ? m.turn : -1;
      if (t != thinking) setState(() => thinking = t);
      return;
    }
    if (widget.bots == null || paused || !ready || m.over) return;
    if (m.phase == 'round') {
      for (var p = 0; p < m.players; p++) {
        if (isBot(p) && !m.nextOk[p]) session.input(p, {'a': 'next'});
      }
      return;
    }
    final p = m.turn;
    if (!isBot(p) || flyTile >= 0 || covered) {
      if (thinking >= 0) setState(() => thinking = -1);
      _botAt = -1;
      return;
    }
    if (_botAt < 0 || _botTurn != p) {
      _botTurn = p;
      // تأخير طبيعي: الأقوى أسرع شوية
      final base = widget.level == 2 ? 0.7 : 1.0;
      _botAt = time + base + _botRng.nextDouble() * 0.8;
      setState(() => thinking = p);
      return;
    }
    if (time < _botAt) return;
    final mv = DominoBot.move(m, p, botLevel, _botRng);
    if (mv == null) {
      // ما عنده شي وماكو مخزن: المرور يصير وحده
      _botAt = time + 10;
      return;
    }
    session.input(p, mv);
    // سحب: يفكّر ثانية قصيرة بعد كل حجر يسحبه
    _botAt = mv['a'] == 'draw' ? time + 0.4 : -1;
    if (mv['a'] != 'draw') setState(() => thinking = -1);
  }

  @override
  void update(double dt) {
    // على نفس الجهاز: الوقت يوقف وهو يسلّم التلفون
    if (!covered) session.update(dt);
    for (final e in session.takeEvents()) {
      // حركتي انعرضت قبل (متوقعة): ما نعيدها
      if (e['e'] == 'play' && _predShown.remove(e['t'])) continue;
      _onEvent(e);
    }
    _afterEvents(dt);
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['e']) {
      case 'play':
        // القطعة تنزل من مكان اللاعب، والصوت لمّن توصل
        flyTile = e['t'] as int;
        flyFrom = rel(e['p'] as int);
        flyAt = time;
        // قطعتي: تطير من مكانها الحقيقي (اليد أو وين فلّتها)
        final l = _launch;
        if (l != null && l.t == flyTile) {
          flyFromPt = l.from;
          flyVertical = l.vertical;
        } else {
          flyFromPt = null;
          flyVertical = true;
        }
        _launch = null;
        Sfx.play('whoosh', volume: 0.35);
        final pts = (e['pts'] as num?)?.toInt() ?? 0;
        if (pts > 0) floats.add((t: flyTile, pts: pts, at: time + flyLen));
      case 'draw':
        Sfx.play('pop', volume: 0.6);
        _bubble(e['p'] as int, 'سحب ${e['n']}');
      case 'pass':
        Sfx.play('tick', volume: 0.6);
        _bubble(e['p'] as int, 'مرّر!');
      case 'round':
        roundShownAt = time;
        final s = e['side'] as int;
        final mine = vp >= 0 && s == m.sideOf(vp);
        if (s >= 0 && (mine || !online)) {
          Sfx.play('gold');
        } else {
          Sfx.play('freeze', volume: 0.7);
        }
        Fx.mid();
      case 'win':
        endAt = time;
        Sfx.play('win');
        Fx.big();
    }
  }

  void _afterEvents(double dt) {
    // وصلت القطعة: تنرسم بالطاولة
    // السحب الراجع لليد خلص
    final dg = drag.value;
    if (dg != null && dg.backAt >= 0 && time - dg.backAt > _Drag.backDur) drag.value = null;
    if (flyTile >= 0 && time - flyAt >= (flyFromPt != null ? flyDurMine : flyDur)) {
      landT = flyTile;
      landAt = time;
      flyTile = -1;
      boardVer.value++;
      Sfx.play('clack');
      Fx.hit();
      if (floats.isNotEmpty && floats.last.t == landT) Sfx.play('gold', volume: 0.6);
    }
    floats.removeWhere((f) => time - f.at > floatDur);
    // الكاميرا تمشي بنعومة للهدف (تصغير وتمركز)
    final c = cam, ct = camTarget;
    if (c != null && ct != null && (c.u != ct.u || c.center != ct.center)) {
      final k = 1 - math.exp(-dt * 7);
      final n = BoardCam.lerp(c, ct, k);
      cam = (n.u - ct.u).abs() < 0.05 && (n.center - ct.center).distance < 0.01 ? ct : n;
      boardVer.value++;
    }
    if (bubbles.isNotEmpty && time - bubbles.first.at > bubbleDur) {
      bubbles.removeWhere((b) => time - b.at > bubbleDur);
      setState(() {});
    }
    if (!ready) return;
    if (!online && !isBot(m.turn) && m.phase == 'play') _lastHuman = m.turn;
    _driveBots();
    final tiles = m.chain.length + m.up.length + m.dn.length;
    final sig = '$tiles|${m.turn}|${m.phase}|${m.hands.map((h) => h.length)}|${m.side}|${m.over}|${m.pile.length}|${m.round}|${m.nextOk}';
    if (sig != _sig) {
      final chainChanged = _sig.split('|').first != '$tiles' || m.chain.isEmpty;
      _sig = sig;
      if (chainChanged) boardVer.value++;
      selected = -1;
      if (drag.value != null && drag.value!.backAt < 0) drag.value = null;
      setState(() {});
    }
    final left = m.timeLeft.ceil();
    final myTurn = m.phase == 'play' && m.turn == vp && !hidden;
    if (myTurn && left <= 5 && left > 0 && left != _lastTick) {
      _lastTick = left;
      Sfx.play('tick', volume: 0.5);
    }
    final shouldShow = m.over && time - endAt > 1.4;
    if (shouldShow != showOver) setState(() => showOver = shouldShow);
  }

  void _bubble(int p, String text) {
    bubbles.removeWhere((b) => b.p == p);
    bubbles.add((p: p, text: text, at: time));
    setState(() {});
  }

  // ------------------------------------------------------------ الحركات

  bool get myTurn => ready && !m.over && m.phase == 'play' && vp >= 0 && m.turn == vp && !hidden && !paused;

  /// ضغطة على حجر: يختاره (يرتفع وتطلع أماكنه). ما ينفع = يهتز.
  /// ضغطة ثانية بسرعة على حجر إله مكان واحد = يلعبه (إذا الخيار مشغّل).
  void _tapTile(int t) {
    if (!myTurn) return;
    final sides = m.sidesFor(t);
    if (sides.isEmpty) {
      setState(() {
        shakeTile = t;
        shakeN++;
        selected = -1;
      });
      Sfx.play('tick', volume: 0.4);
      Fx.tap();
      return;
    }
    final again = _lastTapTile == t && time - _lastTapAt < 0.4 && selected == t;
    _lastTapTile = t;
    _lastTapAt = time;
    if (again && sides.length == 1 && Profile.I.quickTap) {
      _playFromHand(t, sides.first);
      return;
    }
    setState(() => selected = selected == t && !again ? -1 : t);
    Fx.tap();
  }

  /// يلعب من اليد: القطعة تطير من مكانها باليد
  void _playFromHand(int t, String s) {
    final from = _tileCenterOnBoard(t);
    if (from != null) _launch = (t: t, from: from, vertical: true);
    _play(t, s);
  }

  void _play(int t, String s) {
    final mv = {'a': 'play', 't': t, 's': s};
    if (online && vp >= 0) {
      // نعرض الحركة فوراً على نسخة، والسيرفر يأكدها بعدين (بدون انتظار الشبكة)
      try {
        final p = DominoModel.restore(m.toJson());
        p.input(vp, mv);
        final ev = p.drainEvents().where((x) => x['e'] == 'play' && x['t'] == t).toList();
        if (ev.isNotEmpty) {
          _pred = p;
          _predTile = t;
          _predAt = time;
          _predShown.add(t);
          _onEvent(ev.first);
        }
      } catch (_) {}
    }
    session.input(vp, mv);
    setState(() => selected = -1);
  }

  // ------------------------------------------------------------ الإحداثيات

  RenderBox? _box(GlobalKey k) {
    final b = k.currentContext?.findRenderObject();
    return b is RenderBox && b.attached ? b : null;
  }

  Offset? boardLocal(Offset global) => _box(_boardKey)?.globalToLocal(global);
  Offset? rootLocal(Offset global) => _box(_rootKey)?.globalToLocal(global);
  Offset? boardToRoot(Offset local) {
    final b = _box(_boardKey);
    return b == null ? null : rootLocal(b.localToGlobal(local));
  }

  /// مستطيل حجر اليد بإحداثيات الشاشة
  Rect? _tileGlobalRect(int t) {
    final b = _tileKeys[t] == null ? null : _box(_tileKeys[t]!);
    if (b == null) return null;
    return b.localToGlobal(Offset.zero) & b.size;
  }

  Offset? _tileCenterOnBoard(int t) {
    final r = _tileGlobalRect(t);
    return r == null ? null : boardLocal(r.center);
  }

  /// أقرب مكان ينفع للحجر t قرب نقطة بالطاولة (null = بعيد)
  String? _nearestArm(int t, Offset local, double maxDist) {
    final l = lay, c = cam;
    if (l == null || c == null) return null;
    final w = c.toWorld(local, _boardSize);
    String? best;
    var bd = maxDist;
    for (final arm in m.sidesFor(t)) {
      final g = l.ghosts[arm];
      if (g == null) continue;
      final dd = (g.center - w).distance;
      if (dd < bd) {
        bd = dd;
        best = arm;
      }
    }
    return best;
  }

  // ------------------------------------------------------------ السحب

  void _dragStart(int t, DragStartDetails d) {
    if (!myTurn) return;
    final home = _tileGlobalRect(t);
    if (home == null) return;
    if (m.sidesFor(t).isEmpty) {
      _tapTile(t); // يهتز
      return;
    }
    drag.value = _Drag(t, d.globalPosition, d.globalPosition - home.center, home);
    setState(() => selected = t);
    Fx.tap();
  }

  void _dragUpdate(int t, DragUpdateDetails d) {
    final g = drag.value;
    if (g == null || g.t != t || g.backAt >= 0) return;
    final local = boardLocal(d.globalPosition - g.grab);
    final arm = local == null ? null : _nearestArm(t, local, 2.6);
    if (arm != g.snap) Fx.tap(); // التصاق
    drag.value = g.copy(pos: d.globalPosition, snap: arm);
  }

  void _dragEnd(int t) {
    final g = drag.value;
    if (g == null || g.t != t || g.backAt >= 0) return;
    // نعيد الحساب من آخر مكان (إذا السحب كان سريع وما وصلت تحديثات)
    final local = boardLocal(g.pos - g.grab);
    final arm = g.snap ?? (local == null ? null : _nearestArm(t, local, 2.6));
    if (arm != null && myTurn && m.sidesFor(t).contains(arm)) {
      // من المكان الملتصق: نزلة قصيرة بدون لفّة
      final gr = lay?.ghosts[arm];
      final c = cam;
      if (gr != null && c != null) _launch = (t: t, from: c.rectToScreen(gr, _boardSize).center, vertical: false);
      drag.value = null;
      _play(t, arm);
    } else {
      // يرجع لليد بنعومة
      drag.value = g.copy(backAt: time, backFrom: g.pos - g.grab);
    }
  }

  void _tapBoard(TapUpDetails d) {
    if (selected < 0 || !myTurn) return;
    // أقرب مكان وضع ينفع للقطعة (منطقة اللمس أكبر من الظل)
    final best = _nearestArm(selected, d.localPosition, 2.4);
    if (best != null) {
      _playFromHand(selected, best);
    } else {
      setState(() => selected = -1); // ضغطة برا = إلغاء الاختيار
    }
  }

  // ------------------------------------------------------------ الواجهة

  String nameOf(int p) {
    if (!online) {
      if (isBot(p)) {
        final k = widget.bots!.where((b) => b).length;
        return k == 1 ? 'الكمبيوتر' : 'كمبيوتر ${widget.bots!.sublist(0, p + 1).where((b) => b).length}';
      }
      if (widget.bots != null && humans.length == 1) return 'أنت';
      return C.playerNames[p];
    }
    return p == session.me ? 'أنت' : session.nameOf(p);
  }

  Color colorOf(int p) {
    final r = widget.room;
    final seat = r != null && p < r.seats.length ? r.seats[p] : p;
    return C.players[seat % C.players.length];
  }

  /// اسم الجهة (لاعب أو فريق)
  String sideName(int s) {
    if (m.players == 2) return nameOf(s);
    final me = online ? session.me : (humans.length == 1 ? humans.first : -1);
    if (me >= 0 && m.sideOf(me) == s) return 'فريقك';
    return '${nameOf(s)} و${nameOf(s + 2)}';
  }

  String get _status {
    if (m.phase == 'round') {
      final who = m.lastSide >= 0 ? sideName(m.lastSide) : '';
      return switch (m.lastKind) {
        'domino' => '${nameOf(m.lastBy)} خلّص قطعه! +${m.lastPts} لـ$who',
        'block' => 'تسكّرت! الأقل مجموعًا: $who +${m.lastPts}',
        _ => 'تسكّرت بالتعادل، لا نقاط',
      };
    }
    if (myTurn) {
      if (m.mustStart >= 0) return 'ابدأ بالقطعة المزدوجة الكبيرة';
      if (!m.canMove(vp)) return m.pile.isNotEmpty ? 'لا توجد قطعة مناسبة، اسحب من المخزن' : 'لا توجد قطعة مناسبة، تمرير...';
      return selected >= 0 ? 'اختر مكان الحجر على الطاولة' : 'دورك';
    }
    if (isBot(m.turn)) return '${nameOf(m.turn)} يفكّر...';
    return 'دور ${nameOf(m.turn)}';
  }

  /// لوحة المخزن مفتوحة
  bool boneyard = false;

  /// لون جهتي وجهة الخصم (للمناطق الملوّنة)
  Color get _myColor => vp >= 0 ? colorOf(vp) : C.accent;

  @override
  Widget build(BuildContext context) {
    final hasRoom = widget.room != null;
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      showPause: false,
      child: Stack(
        key: _rootKey,
        children: [
          const Positioned.fill(child: _Felt()),
          if (!ready)
            const NetWaiting()
          else
            SafeArea(
              child: Padding(
                // أونلاين زر التفاعلات على اليسار
                padding: EdgeInsets.fromLTRB(hasRoom ? 60 : 8, 6, 8, 6),
                child: Column(
                  children: [
                    _topBar(),
                    const SizedBox(height: 6),
                    _scoreBar(),
                    const SizedBox(height: 6),
                    _opponentsTop(),
                    Expanded(
                      child: Row(
                        children: [
                          if (m.players == 4) _sideSeat((vp < 0 ? 0 : vp) + 3),
                          Expanded(child: _board()),
                          if (m.players == 4) _sideSeat((vp < 0 ? 0 : vp) + 1),
                        ],
                      ),
                    ),
                    // منطقتي بلوني
                    Container(
                      padding: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [alpha(_myColor, 0.04), alpha(_myColor, 0.2)],
                        ),
                        border: Border(top: BorderSide(color: alpha(_myColor, 0.35))),
                      ),
                      child: Column(children: [
                        _statusRow(),
                        const SizedBox(height: 2),
                        _hand(),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          if (ready)
            for (final b in bubbles) _bubbleView(b),
          if (ready && thinking >= 0 && m.phase == 'play') _thinkingView(thinking),
          // الحجر المسحوب (فوق كل شي)
          if (ready) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _DragPainter(this)))),
          if (ready && boneyard) Positioned.fill(child: _boneyardPanel()),
          if (ready && m.phase == 'round' && !m.over) Positioned.fill(child: _roundPanel()),
          if (ready && online) NetBanner(session: session, players: m.players),
          if (ready && covered) Positioned.fill(child: _cover()),
          if (showOver)
            Positioned.fill(
              child: ResultOverlay(
                winner: m.winSide,
                scores: m.side,
                seats: m.players == 4 ? const [0, 1] : null,
                names: [sideName(0), sideName(1)],
                menuLabel: online ? 'الغرفة' : null,
                onMenu: roomMenu(context, session),
                session: session,
                againLabel: againLabelOf(session),
                footer: tourFooter(session),
                onAgain: restart,
              ),
            ),
        ],
      ),
    );
  }

  /// فقاعة "مرّر!" أو "سحب" تطلع بمكان اللاعب وتختفي
  Widget _bubbleView(({int p, String text, double at}) b) {
    final r = rel(b.p);
    final align = r == 0
        ? const Alignment(0, 0.5)
        : isTop(r)
            ? const Alignment(0, -0.6)
            : r == 1
                ? const Alignment(-0.72, 0)
                : const Alignment(0.72, 0);
    return Align(
      alignment: align,
      child: IgnorePointer(
        child: ValueListenableBuilder<int>(
          valueListenable: frame,
          builder: (context, _, __) {
            final age = time - b.at;
            final pop = Curves.elasticOut.transform((age / 0.45).clamp(0.0, 1.0));
            final fade = age < bubbleDur - 0.35 ? 1.0 : ((bubbleDur - age) / 0.35).clamp(0.0, 1.0);
            final c = colorOf(b.p);
            return Opacity(
              opacity: fade,
              child: Transform.scale(
                scale: 0.4 + 0.6 * pop,
                child: Transform.translate(
                  offset: Offset(0, -10 * (age / bubbleDur)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c, width: 3),
                      boxShadow: const [BoxShadow(color: Color(0x55000000), offset: Offset(0, 3))],
                    ),
                    child: Text(b.text, style: display(22, color: darken(c, 0.35))),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _scoreBar() {
    Widget chip(int s) {
      final c = m.players == 4 ? C.players[s] : colorOf(s);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: alpha(c, 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: alpha(c, 0.6)),
          ),
          child: Row(
            children: [
              Expanded(child: Text(sideName(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(13, weight: FontWeight.w800))),
              Text('${m.side[s]}', style: display(24, color: c)),
              Text(' / ${m.target}', style: body(11, color: C.muted)),
            ],
          ),
        ),
      );
    }

    final mine = vp >= 0 ? m.sideOf(vp) : 0;
    return Row(children: [chip(mine), const SizedBox(width: 8), chip(1 - mine)]);
  }

  /// قطع لاعب: مروحة متراكبة قريبة من صورته (ظهرها، أو مكشوفة بنتيجة الجولة)
  Widget _miniHand(int p, {bool vertical = false}) {
    final h = m.hands[p];
    if (h.isEmpty) return const SizedBox.shrink();
    // مكشوفة بنتيجة الجولة: أكبر شوية حتى تنقرا
    final open = m.phase != 'play' || m.over;
    final s = open ? 13.0 : 12.0;
    final step = open ? s + 2 : s * 0.55; // متراكبة وهي مقلوبة، ومتفرقة وهي مكشوفة
    final tw = vertical ? s * 2 : s, th = vertical ? s : s * 2;
    final n = h.length;
    final w = vertical ? tw : tw + step * (n - 1);
    final hh = vertical ? th + step * (n - 1) : th;
    return SizedBox(
      width: w,
      height: hh,
      child: Stack(
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: vertical ? 0 : step * i,
              top: vertical ? step * i : 0,
              width: tw,
              height: th,
              // على نفس الجهاز الموديل يعرف كل القطع، فنقلبها هنا (إلا بنتيجة الجولة)
              child: CustomPaint(painter: _TilePainter(h[i], faceDown: h[i] < 0 || (!online && !open))),
            ),
        ],
      ),
    );
  }

  /// صورة اللاعب وجنبها عدد قطعه (والدور يلمع)
  Widget _avatarBadge(int p) {
    final turn = m.phase == 'play' && m.turn == p;
    final room = widget.room;
    final avatar = room != null && p < room.seats.length ? room.avatarOfSeat(room.seats[p]) : '';
    final c = colorOf(p);
    return SizedBox(
      width: 46,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 3,
            top: 0,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: alpha(c, 0.3),
                shape: BoxShape.circle,
                border: Border.all(color: turn ? _gold : c, width: turn ? 3 : 2),
              ),
              child: avatar.isEmpty
                  ? Container(width: 18, height: 18, decoration: BoxDecoration(color: c, shape: BoxShape.circle))
                  : Avatar(avatar, size: 26),
            ),
          ),
          // عدد القطع
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F1E3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c, width: 2),
              ),
              child: Text('${m.hands[p].length}', textAlign: TextAlign.center, style: body(12, weight: FontWeight.w900, color: const Color(0xFF1C1A22))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seatLabel(int p, {bool compact = false}) {
    final turn = m.phase == 'play' && m.turn == p;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: alpha(colorOf(p), turn ? 0.35 : 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: alpha(colorOf(p), turn ? 1 : 0.5), width: turn ? 2 : 1),
      ),
      child: compact
          ? Column(
              children: [
                _avatarBadge(p),
                Text(nameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(11, weight: FontWeight.w800)),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatarBadge(p),
                const SizedBox(width: 6),
                Flexible(child: Text(nameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(13, weight: FontWeight.w800))),
                const SizedBox(width: 4),
              ],
            ),
    );
  }

  Widget _opponentsTop() {
    final base = vp < 0 ? 0 : vp;
    final p = m.players == 2 ? (base + 1) % 2 : (base + 2) % 4;
    // منطقة الخصم بلونه
    final c = colorOf(p);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [alpha(c, 0.2), alpha(c, 0.04)]),
        border: Border(bottom: BorderSide(color: alpha(c, 0.3))),
      ),
      child: Column(
        children: [
          _seatLabel(p),
          const SizedBox(height: 4),
          _miniHand(p),
        ],
      ),
    );
  }

  Widget _sideSeat(int raw) {
    final p = raw % 4;
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _seatLabel(p, compact: true),
          const SizedBox(height: 4),
          _miniHand(p, vertical: true),
        ],
      ),
    );
  }

  Widget _board() {
    return LayoutBuilder(builder: (context, box) {
      return GestureDetector(
        key: const ValueKey('board'), // للاختبارات
        behavior: HitTestBehavior.opaque,
        onTapUp: _tapBoard,
        child: Stack(
          key: _boardKey,
          children: [
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _BoardPainter(this)))),
            // دوري: الجهات اللي تنفع تتلوّن، والقطعة النازلة تتحرك
            if (myTurn) Positioned.fill(child: CustomPaint(painter: _MarksPainter(this))),
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FlyPainter(this)))),
            // قطع السحب (بلاعبين)
            if (m.players == 2) Positioned(top: 4, left: 4, child: _stock()),
          ],
        ),
      );
    });
  }

  bool get canDraw => myTurn && !m.canMove(vp) && m.pile.isNotEmpty;

  /// المخزن: كومة ويا عددها، تنضغط وتفتح اللوحة (تنبض لمّن لازم تسحب)
  Widget _stock() {
    final n = m.pile.length;
    return GestureDetector(
      onTap: n == 0 ? null : () => setState(() => boneyard = true),
      child: Opacity(
        opacity: n == 0 ? 0.45 : 1,
        child: ValueListenableBuilder<int>(
          valueListenable: frame,
          builder: (context, _, child) {
            final pulse = canDraw ? 1 + 0.08 * math.sin(time * 7) : 1.0;
            return Transform.scale(scale: pulse, child: child);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 3),
            decoration: BoxDecoration(
              color: alpha(Colors.black, 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: alpha(canDraw ? _gold : Colors.white, canDraw ? 0.9 : 0.15), width: canDraw ? 2 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 30,
                  height: 34,
                  child: Stack(
                    children: [
                      for (var i = 0; i < math.min(3, math.max(1, n)); i++)
                        Positioned(
                          left: i * 3.0,
                          top: 6 - i * 3.0,
                          width: 24,
                          height: 26,
                          child: CustomPaint(painter: _TilePainter(-1, faceDown: true)),
                        ),
                    ],
                  ),
                ),
                Text(n == 0 ? 'فارغ' : 'المخزن $n', style: body(11, weight: FontWeight.w800, color: alpha(Colors.white, 0.85))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// لوحة المخزن: الأحجار الباقية مقلوبة، وضغطة على حجر تسحبه
  Widget _boneyardPanel() {
    final n = m.pile.length;
    final can = canDraw;
    return GestureDetector(
      onTap: () => setState(() => boneyard = false),
      child: Container(
        color: alpha(Colors.black, 0.6),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () {}, // الضغط داخل اللوحة ما يسكّرها
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration:
                BoxDecoration(color: const Color(0xFF123B2E), borderRadius: BorderRadius.circular(24), border: Border.all(color: alpha(_gold, 0.5), width: 2)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('المخزن', style: display(30, color: _gold)),
                Text(
                  n == 0
                      ? 'لم يبقَ شيء في المخزن'
                      : can
                          ? 'اضغط على حجر لتسحبه ($n)'
                          : (myTurn ? 'لديك حجر مناسب، العبه أولًا' : 'تسحب في دورك فقط ($n)'),
                  textAlign: TextAlign.center,
                  style: body(14, color: alpha(Colors.white, 0.85)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < n; i++)
                      GestureDetector(
                        onTap: can
                            ? () {
                                session.input(vp, {'a': 'draw'});
                                Fx.tap();
                                // تسكّر وحدها إذا صار عندك حجر ينلعب أو خلص المخزن
                                if (m.canMove(vp) || m.pile.isEmpty || m.phase != 'play') setState(() => boneyard = false);
                              }
                            : null,
                        child: Opacity(
                          opacity: can ? 1 : 0.55,
                          child: SizedBox(width: 30, height: 56, child: CustomPaint(painter: _TilePainter(-1, faceDown: true))),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                BigButton(label: 'إغلاق', filled: false, onTap: () => setState(() => boneyard = false)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// الشريط العلوي: رجوع، صوت، إعادة، إعدادات، والمستوى والهدف
  Widget _topBar() {
    Widget icon(IconData i, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: GlassIconButton(icon: i, onTap: onTap, size: 38),
        );
    final lv = widget.level ?? (m.level >= 0 ? m.level : -1);
    return Row(
      children: [
        icon(Icons.arrow_forward_rounded, openPause),
        icon(Sfx.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, () {
          Profile.I.setSound(!Sfx.enabled);
          setState(() {});
        }),
        if (!online) icon(Icons.replay_rounded, _confirmRestart),
        icon(Icons.tune_rounded, _settings),
        const SizedBox(width: 4),
        // يصغر إذا الشاشة ضيقة (التلفون الصغير)
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: alpha(Colors.black, 0.25), borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (lv >= 0) ...[
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: kLevelColors[lv], shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(kLevelNames[lv], style: body(13, weight: FontWeight.w800, color: kLevelColors[lv])),
                    Text('  •  ', style: body(12, color: C.muted)),
                  ],
                  Text('الهدف ${m.goal}', style: body(13, weight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRestart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('إعادة اللعبة؟', style: display(26)),
        content: Text('ستبدأ مباراة جديدة من الصفر.', style: body(15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: body(15, color: C.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('إعادة', style: body(15, weight: FontWeight.w900, color: _gold))),
        ],
      ),
    );
    if (ok == true && mounted) restart();
  }

  Future<void> _settings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: C.surface,
          title: Text('الإعدادات', style: display(26)),
          content: SwitchListTile(
            value: Profile.I.quickTap,
            activeThumbColor: _gold,
            contentPadding: EdgeInsets.zero,
            title: Text('ضغطتان تلعبان الحجر', style: body(15, weight: FontWeight.w800)),
            subtitle: Text('إذا كان للحجر مكان واحد، اضغط عليه مرتين بسرعة ليُلعب مباشرة', style: body(13, color: C.muted)),
            onChanged: (v) {
              Profile.I.setQuickTap(v);
              set(() {});
            },
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('تم', style: body(15, weight: FontWeight.w900, color: _gold)))],
        ),
      ),
    );
  }

  /// مكان اللاعب بالشاشة (للفقاعات)
  Alignment _seatAlign(int p) {
    final r = rel(p);
    return r == 0
        ? const Alignment(0, 0.5)
        : isTop(r)
            ? const Alignment(0, -0.45)
            : r == 1
                ? const Alignment(-0.72, 0)
                : const Alignment(0.72, 0);
  }

  /// فقاعة "يفكّر..." فوق الكمبيوتر (نقاط تتحرك)
  Widget _thinkingView(int p) {
    final c = colorOf(p);
    return Align(
      alignment: _seatAlign(p),
      child: IgnorePointer(
        child: ValueListenableBuilder<int>(
          valueListenable: frame,
          builder: (context, _, __) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c, width: 3),
                boxShadow: const [BoxShadow(color: Color(0x55000000), offset: Offset(0, 3))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.smart_toy_rounded, size: 20, color: darken(c, 0.3)),
                const SizedBox(width: 4),
                Text('يفكّر', style: display(19, color: darken(c, 0.35))),
                const SizedBox(width: 3),
                // ثلاث نقاط تنط بالدور
                CustomPaint(size: const Size(20, 10), painter: _DotsPainter(time, darken(c, 0.35))),
              ]),
            );
          },
        ),
      ),
    );
  }

  /// نتيجة الجولة: شريط "لا توجد حركات ممكنة" إذا تسكّرت، وبعدها نافذة النقاط و"الجولة التالية"
  Widget _roundPanel() {
    final age = time - roundShownAt;
    final blocked = m.lastKind == 'block' || m.lastKind == 'tie';
    if (blocked && age < 1.4) {
      return IgnorePointer(
        child: Center(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            color: alpha(Colors.black, 0.7),
            child: Text('لا توجد حركات ممكنة', textAlign: TextAlign.center, style: display(30, color: _gold)),
          ),
        ),
      );
    }
    if (age < (blocked ? 1.4 : 0.9)) return const SizedBox.shrink();
    final me = online ? session.me : (humans.length == 1 ? humans.first : -1);
    final mySide = me >= 0 ? m.sideOf(me) : -1;
    final w = m.lastSide;
    final title = w < 0
        ? 'تعادل في هذه الجولة'
        : mySide < 0
            ? 'الجولة لـ${sideName(w)}'
            : (w == mySide ? 'فزت بالجولة!' : 'خسرت الجولة');
    final reached = m.side.any((s) => s >= m.goal) && m.side[0] != m.side[1];
    final waiting = online && me >= 0 && m.nextOk[me];
    Widget row(int s) {
      final c = m.players == 4 ? C.players[s] : colorOf(s);
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: alpha(c, 0.16), borderRadius: BorderRadius.circular(14), border: Border.all(color: alpha(c, s == w ? 1 : 0.5), width: s == w ? 2 : 1)),
        child: Row(children: [
          Expanded(child: Text(sideName(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(15, weight: FontWeight.w800))),
          Text('+${m.roundPts[s]}', style: display(22, color: m.roundPts[s] > 0 ? _gold : C.muted)),
          const SizedBox(width: 12),
          Text('${m.side[s]}', style: display(26, color: c)),
        ]),
      );
    }

    return Container(
      color: alpha(Colors.black, 0.55),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: _FadeIn(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration:
              BoxDecoration(color: const Color(0xFF123B2E), borderRadius: BorderRadius.circular(26), border: Border.all(color: alpha(_gold, 0.6), width: 2)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, textAlign: TextAlign.center, style: display(32, color: w >= 0 && w == mySide ? _gold : Colors.white)),
              const SizedBox(height: 2),
              Text(_status, textAlign: TextAlign.center, style: body(14, color: alpha(Colors.white, 0.8))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('الجولة ${m.round + 1}', style: body(13, color: C.muted))),
                Text('الهدف ${m.goal}', style: body(13, weight: FontWeight.w800, color: _gold)),
              ]),
              for (final s in [if (mySide >= 0) mySide, 1 - (mySide >= 0 ? mySide : 1), if (mySide < 0) 1]) row(s),
              const SizedBox(height: 12),
              waiting
                  ? Text('بانتظار الآخرين...', style: body(15, color: C.muted))
                  : BigButton(
                      label: reached ? 'النتيجة النهائية' : 'الجولة التالية',
                      icon: Icons.arrow_back_rounded,
                      color: _gold,
                      onTap: () {
                        if (online) {
                          if (me >= 0) session.input(me, {'a': 'next'});
                        } else {
                          for (final p in humans) {
                            session.input(p, {'a': 'next'});
                          }
                        }
                        Fx.tap();
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusRow() {
    final timed = m.phase == 'play' && !m.over;
    return Column(
      children: [
        Text(_status, textAlign: TextAlign.center, style: body(16, weight: FontWeight.w800)),
        if (timed) ...[
          const SizedBox(height: 4),
          SizedBox(height: 5, width: 200, child: CustomPaint(painter: _TimerBar(this))),
        ],
        if (canDraw) ...[
          const SizedBox(height: 6),
          BigButton(label: 'اسحب من المخزن', icon: Icons.add_rounded, color: _gold, onTap: () => setState(() => boneyard = true)),
        ],
      ],
    );
  }

  Widget _hand() {
    if (vp < 0) return const SizedBox(height: 8);
    if (hidden) return const SizedBox(height: _handH);
    final h = m.hands[vp];
    final mine = myTurn;
    final ok = mine ? m.playable(vp).toSet() : const <int>{};
    return SizedBox(
      height: _handH,
      child: LayoutBuilder(builder: (context, box) {
        // كل الأحجار تبين بدون تمرير: تصغر شوية إذا كثرت (السحب)
        final n = math.max(1, h.length);
        final w = math.min(36.0, (box.maxWidth / n) - 6).clamp(16.0, 36.0);
        return ValueListenableBuilder<_Drag?>(
          valueListenable: drag,
          builder: (context, dg, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final t in h)
                GestureDetector(
                  // منطقة اللمس أكبر من الحجر
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tapTile(t),
                  onPanStart: mine ? (d) => _dragStart(t, d) : null,
                  onPanUpdate: mine ? (d) => _dragUpdate(t, d) : null,
                  onPanEnd: mine ? (_) => _dragEnd(t) : null,
                  onPanCancel: mine ? () => _dragEnd(t) : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(3, 10, 3, 4),
                    child: _shake(
                      t,
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutBack,
                        offset: Offset(0, selected == t ? -0.18 : 0),
                        child: Opacity(
                          key: ValueKey('hand-$t'), // للاختبارات
                          opacity: dg != null && dg.t == t ? 0.25 : 1,
                          child: SizedBox(
                            key: _tileKeys.putIfAbsent(t, GlobalKey.new),
                            width: w,
                            height: w * 2,
                            child: CustomPaint(
                              painter:
                                  _TilePainter(t, glow: m.hints && ok.contains(t), dim: m.hints && mine && !ok.contains(t), selected: mine && selected == t),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  static const _handH = 90.0;

  /// اهتزازة خفيفة للحجر اللي ما ينفع
  Widget _shake(int t, Widget child) {
    if (shakeTile != t) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey('shake$shakeN'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      builder: (context, v, c) => Transform.translate(offset: Offset(math.sin(v * math.pi * 6) * 6 * (1 - v), 0), child: c),
      child: child,
    );
  }

  /// على نفس الجهاز: "سلّم التلفون" حتى ما يشوف قطع غيره
  Widget _cover() {
    final p = m.turn;
    return Container(
      color: const Color(0xFF071A14), // معتمة تماماً حتى ما تبين القطع
      alignment: Alignment.center,
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 64, height: 64, decoration: BoxDecoration(color: colorOf(p), shape: BoxShape.circle)),
          const SizedBox(height: 16),
          Text('دور ${nameOf(p)}', style: display(38, color: colorOf(p))),
          const SizedBox(height: 6),
          Text('سلّم الهاتف إلى ${nameOf(p)}، ولا ينظر غيره إلى القطع.', textAlign: TextAlign.center, style: body(16, color: C.muted)),
          const SizedBox(height: 22),
          BigButton(label: 'أنا جاهز', icon: Icons.visibility_rounded, color: colorOf(p), onTap: () => setState(() => _readyFor = p)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ الرسم

class _Felt extends StatelessWidget {
  const _Felt();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(radius: 1.1, colors: [Color(0xFF16684F), _felt, Color(0xFF07261C)], stops: [0, 0.6, 1]),
      ),
    );
  }
}

class _TimerBar extends CustomPainter {
  _TimerBar(this.s) : super(repaint: s.frame);
  final _DominoState s;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = alpha(Colors.white, 0.12));
    final f = (s.m.timeLeft / s.m.turnTime).clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * f, size.height), r),
      Paint()..color = f < 0.2 ? const Color(0xFFFF4D6A) : _gold,
    );
  }

  @override
  bool shouldRepaint(_TimerBar old) => true;
}

/// مواقع النقط بنص القطعة (3×3)
const _pipSpots = <List<(int, int)>>[
  [],
  [(1, 1)],
  [(0, 0), (2, 2)],
  [(0, 0), (1, 1), (2, 2)],
  [(0, 0), (2, 0), (0, 2), (2, 2)],
  [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
  [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
];

/// قطعة دومينو. [a] بأول نص (يسار أو فوق)، [b] بالثاني.
void paintTile(Canvas canvas, Rect r, int a, int b, {bool faceDown = false, bool glow = false, bool dim = false, bool selected = false}) {
  final rad = Radius.circular(r.shortestSide * 0.16);
  final rr = RRect.fromRectAndRadius(r, rad);
  // ظل بسيط (بدون تمويه)
  canvas.drawRRect(rr.shift(Offset(0, r.shortestSide * 0.06)), Paint()..color = alpha(Colors.black, 0.3));
  if (faceDown) {
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF2B2140));
    canvas.drawRRect(
      rr.deflate(r.shortestSide * 0.12),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.shortestSide * 0.06
        ..color = alpha(_gold, 0.5),
    );
    return;
  }
  canvas.drawRRect(rr, Paint()..color = dim ? const Color(0xFF9A978E) : const Color(0xFFF7F1E3));
  if (selected) {
    // المختار: إطار أصفر عريض ويا هالة
    canvas.drawRRect(rr.inflate(5), Paint()..color = alpha(const Color(0xFFFFE34D), 0.25));
    canvas.drawRRect(
      rr.inflate(2.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFFFE34D),
    );
  } else if (glow) {
    canvas.drawRRect(
      rr.inflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _gold,
    );
  }
  final vertical = r.height > r.width;
  final s = r.shortestSide;
  final line = Paint()
    ..color = alpha(Colors.black, 0.35)
    ..strokeWidth = math.max(1, s * 0.05);
  if (vertical) {
    canvas.drawLine(Offset(r.left + s * 0.15, r.center.dy), Offset(r.right - s * 0.15, r.center.dy), line);
  } else {
    canvas.drawLine(Offset(r.center.dx, r.top + s * 0.15), Offset(r.center.dx, r.bottom - s * 0.15), line);
  }
  final pip = Paint()..color = dim ? const Color(0xFF4A4740) : const Color(0xFF1C1A22);
  void half(Rect h, int v) {
    final g = h.deflate(s * 0.2);
    for (final (x, y) in _pipSpots[v]) {
      // بالقطعة الأفقية ندوّر الشبكة حتى الستة تصير صفين
      final (cx, cy) = vertical ? (x, y) : (y, x);
      canvas.drawCircle(Offset(g.left + g.width * cx / 2, g.top + g.height * cy / 2), s * 0.085, pip);
    }
  }

  if (vertical) {
    half(Rect.fromLTWH(r.left, r.top, r.width, r.height / 2), a);
    half(Rect.fromLTWH(r.left, r.center.dy, r.width, r.height / 2), b);
  } else {
    half(Rect.fromLTWH(r.left, r.top, r.width / 2, r.height), a);
    half(Rect.fromLTWH(r.center.dx, r.top, r.width / 2, r.height), b);
  }
}

class _TilePainter extends CustomPainter {
  _TilePainter(this.t, {this.faceDown = false, this.glow = false, this.dim = false, this.selected = false});
  final int t;
  final bool faceDown, glow, dim, selected;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t < 0 ? 0 : DominoModel.tileA[t], b = t < 0 ? 0 : DominoModel.tileB[t];
    paintTile(canvas, Offset.zero & size, a, b, faceDown: faceDown || t < 0, glow: glow, dim: dim, selected: selected);
  }

  @override
  bool shouldRepaint(_TilePainter old) => old.t != t || old.glow != glow || old.dim != dim || old.faceDown != faceDown || old.selected != selected;
}

/// نقاط "يفكّر..." تنط وحدة ورا الثانية
class _DotsPainter extends CustomPainter {
  _DotsPainter(this.t, this.c);
  final double t;
  final Color c;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final k = math.max(0.0, math.sin(t * 6 - i * 0.9));
      canvas.drawCircle(Offset(3 + i * 7.0, size.height * 0.7 - k * 4), 2.6, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => true;
}

/// تطلع بحركة (تكبر وتبان) أول ما تنبني
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, t, c) => Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: 0.8 + 0.2 * t, child: c)),
      child: child,
    );
  }
}

/// حجر بإيد اللاعب وهو يسحبه
class _Drag {
  _Drag(this.t, this.pos, this.grab, this.home, {this.snap, this.backAt = -1, this.backFrom = Offset.zero});
  final int t;

  /// مكان الإصبع (شاشة)، والفرق بينه وبين نص الحجر، ومكان الحجر باليد
  final Offset pos, grab;
  final Rect home;

  /// الطرف الملتصق بيه (null = حر)
  final String? snap;

  /// يرجع لليد: من وكت، ومن وين
  final double backAt;
  final Offset backFrom;
  static const backDur = 0.24;

  _Drag copy({Offset? pos, String? snap, double? backAt, Offset? backFrom}) =>
      _Drag(t, pos ?? this.pos, grab, home, snap: backAt != null ? null : snap, backAt: backAt ?? this.backAt, backFrom: backFrom ?? this.backFrom);
}

/// الحجر المسحوب: يلحق الإصبع، يلتصق بالمكان الصالح، أو يرجع لليد بنعومة
class _DragPainter extends CustomPainter {
  _DragPainter(this.s) : super(repaint: Listenable.merge([s.drag, s.frame]));
  final _DominoState s;

  @override
  void paint(Canvas canvas, Size size) {
    final g = s.drag.value;
    if (g == null) return;
    final t = g.t;
    final a = DominoModel.tileA[t], b = DominoModel.tileB[t];
    final hw = g.home.width, hh = g.home.height;
    if (g.backAt >= 0) {
      final k = Curves.easeOutCubic.transform(((s.time - g.backAt) / _Drag.backDur).clamp(0.0, 1.0));
      final p = s.rootLocal(Offset.lerp(g.backFrom, g.home.center, k)!);
      if (p == null) return;
      paintTile(canvas, Rect.fromCenter(center: p, width: hw, height: hh), a, b, glow: true);
      return;
    }
    final l = s.lay, cam = s.cam;
    final arm = g.snap;
    if (arm != null && l != null && cam != null && l.ghosts[arm] != null) {
      // ملتصق: بحجم واتجاه مكانه بالطاولة
      final r = cam.rectToScreen(l.ghosts[arm]!, s._boardSize).deflate(cam.u * 0.04);
      final tl = s.boardToRoot(r.topLeft), br = s.boardToRoot(r.bottomRight);
      if (tl == null || br == null) return;
      final (fa, fb) = l.faceAt(arm, t, s.m.endOf(arm));
      paintTile(canvas, Rect.fromPoints(tl, br), fa, fb, selected: true);
      return;
    }
    // حر: يلحق الإصبع، أكبر شوية ويا ظل
    final p = s.rootLocal(g.pos - g.grab);
    if (p == null) return;
    final rect = Rect.fromCenter(center: p, width: hw * 1.15, height: hh * 1.15);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.shift(const Offset(5, 8)), Radius.circular(rect.shortestSide * 0.16)), Paint()..color = alpha(Colors.black, 0.25));
    paintTile(canvas, rect, a, b, selected: true);
  }

  @override
  bool shouldRepaint(_DragPainter old) => true;
}

/// الطاولة: القطع بأماكنها حسب الكاميرا (تنرسم بس لمّن السلسلة أو الكاميرا تتغير)
class _BoardPainter extends CustomPainter {
  _BoardPainter(this.s) : super(repaint: s.boardVer);
  final _DominoState s;

  @override
  void paint(Canvas canvas, Size size) {
    s.ensureLayout(size);
    final l = s.lay, cam = s.cam;
    if (l == null || cam == null) return;
    final gap = cam.u * 0.04;
    for (final t in l.tiles) {
      if (t.t >= 0 && t.t == s.flyTile) continue; // بعدها نازلة (_FlyPainter)
      paintTile(canvas, cam.rectToScreen(t.rect, size).deflate(gap), t.a, t.b);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}

/// أماكن الوضع: ظل قطعة بكل طرف ينفع (يتنفّس)
class _MarksPainter extends CustomPainter {
  _MarksPainter(this.s) : super(repaint: s.frame);
  final _DominoState s;

  @override
  void paint(Canvas canvas, Size size) {
    s.ensureLayout(size);
    final l = s.lay, cam = s.cam;
    final m = s.m;
    if (l == null || cam == null || s.vp < 0) return;
    final pulse = 0.5 + 0.5 * math.sin(s.time * 6);
    final sel = s.selected >= 0;
    if (!sel && !m.hints) return; // الصعب: بدون تلميح
    final arms = sel ? m.sidesFor(s.selected).toSet() : {for (final t in m.playable(s.vp)) ...m.sidesFor(t)};
    final col = sel ? _gold : C.go;
    for (final arm in arms) {
      final g = l.ghosts[arm];
      if (g == null) continue;
      final r = cam.rectToScreen(g, size).deflate(cam.u * 0.06);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide * 0.18));
      canvas.drawRRect(rr, Paint()..color = alpha(col, (sel ? 0.22 : 0.12) + 0.12 * pulse));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sel ? 3 : 2
          ..color = alpha(col, sel ? 0.95 : 0.6),
      );
      if (sel) canvas.drawCircle(r.center, r.shortestSide * (0.28 + 0.06 * pulse), Paint()..color = alpha(col, 0.5));
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => true;
}

/// القطعة النازلة (تطير بقوس وتلف وتنزل)، وموجة النزول، وأرقام النقاط العائمة
class _FlyPainter extends CustomPainter {
  _FlyPainter(this.s) : super(repaint: s.frame);
  final _DominoState s;

  BoardTile? _find(int t) {
    for (final x in s.lay?.tiles ?? const <BoardTile>[]) {
      if (x.t == t) return x;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    s.ensureLayout(size);
    final cam = s.cam;
    if (cam == null) return;
    final u = cam.u;
    // النزول
    final dest = s.flyTile >= 0 ? _find(s.flyTile) : null;
    if (dest != null) {
      final to = cam.rectToScreen(dest.rect, size);
      final k = ((s.time - s.flyAt) / s.flyLen).clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(k);
      final r = s.flyFrom;
      final mine = s.flyFromPt;
      final from = mine ??
          (r == 0
              ? Offset(size.width / 2, size.height + u * 3)
              : s.isTop(r)
                  ? Offset(size.width / 2, -u * 3)
                  : r == 1
                      ? Offset(-u * 3, size.height / 2)
                      : Offset(size.width + u * 3, size.height / 2));
      // قوس خفيف، ويكبر بالهوا وينزل لحجمه (قطعتي: انزلاق ناعم أقصر)
      final arc = mine != null ? 0.4 : 1.2;
      final c = Offset.lerp(from, to.center, e)! - Offset(0, math.sin(e * math.pi) * u * arc);
      final scale = 1 + (mine != null ? 0.15 : 0.45) * math.sin(e * math.pi) + (mine != null ? 0 : 0.25) * (1 - e);
      // يلف من وضع اليد (عمودي) لاتجاهه بالطاولة
      final turn = s.flyVertical && to.width > to.height ? (1 - e) * (math.pi / 2) : 0.0;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(turn * (r == 0 ? 1 : -1));
      final rect = Rect.fromCenter(center: Offset.zero, width: to.width * scale, height: to.height * scale);
      // ظل على الطاولة يقرب لمّن تنزل
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.shift(Offset(u * 0.3 * (1 - e) + 2, u * 0.5 * (1 - e) + 3)), Radius.circular(rect.shortestSide * 0.16)),
        Paint()..color = alpha(Colors.black, 0.25 * e),
      );
      paintTile(canvas, rect, dest.a, dest.b, glow: true);
      canvas.restore();
    }
    // موجة النزول
    final land = s.landT >= 0 ? _find(s.landT) : null;
    final la = s.time - s.landAt;
    if (land != null && la < 0.45) {
      final r = cam.rectToScreen(land.rect, size);
      final k = la / 0.45;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(u * 0.8 * k), Radius.circular(u * 0.3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - k)
          ..color = alpha(Colors.white, 0.6 * (1 - k)),
      );
    }
    // النقاط العائمة (+10)
    for (final f in s.floats) {
      final age = s.time - f.at;
      if (age < 0) continue;
      final t = _find(f.t);
      if (t == null) continue;
      final k = (age / _DominoState.floatDur).clamp(0.0, 1.0);
      final p = cam.toScreen(t.rect.center, size) - Offset(0, u * (0.6 + 2.2 * Curves.easeOut.transform(k)));
      final pop = Curves.elasticOut.transform((age / 0.5).clamp(0.0, 1.0));
      final fade = k < 0.7 ? 1.0 : (1 - k) / 0.3;
      final tp = TextPainter(
        text: TextSpan(
          text: '+${f.pts}',
          style: display(math.max(22, u * 1.3) * (0.6 + 0.4 * pop),
              color: alpha(_gold, fade), shadows: [Shadow(color: alpha(Colors.black, 0.6 * fade), offset: const Offset(0, 2), blurRadius: 4)]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_FlyPainter old) => true;
}

/// أيقونة اللعبة: قطعتين
class DominoIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.translate(w * 0.5, h * 0.5);
    canvas.rotate(-0.35);
    paintTile(canvas, Rect.fromCenter(center: Offset(-w * 0.16, 0), width: w * 0.3, height: h * 0.6), 6, 3);
    canvas.rotate(0.6);
    paintTile(canvas, Rect.fromCenter(center: Offset(w * 0.2, h * 0.04), width: w * 0.3, height: h * 0.6), 5, 5);
    canvas.restore();
  }

  @override
  bool shouldRepaint(DominoIcon old) => false;
}
