import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../logic/whois_bank.dart';
import '../logic/whois_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/share_card.dart';
import '../ui/art.dart';
import '../ui/theme.dart';

/// منو بينا؟: كل جولة سؤال مضحك والكل يصوّت بسرية على لاعب. أونلاين/محلي بس (كل واحد بتلفونه).
/// القواعد بـ WhoisModel، والسيرفر يخفي الأصوات لحد الكشف.
class WhoisGame extends StatefulWidget {
  const WhoisGame({super.key, required this.room});
  final RoomConn room;

  @override
  State<WhoisGame> createState() => _WhoisState();
}

const _gold = Color(0xFFFFD34D);
const _confettiColors = [Color(0xFFFF5A5F), Color(0xFFFFD34D), Color(0xFF5CE08A), Color(0xFF3D8BFF), Color(0xFFB06CFF), Color(0xFFFF9F43)];

/// قصاصة احتفال (بإحداثيات الشاشة)
class _Bit {
  _Bit(this.p, this.v, this.c, this.spin) : rot = 0;
  Offset p, v;
  final Color c;
  final double spin;
  double rot, life = 2.2;
}

class _WhoisState extends LoopState<WhoisGame> {
  late final OnlineSession<WhoisModel> session = OnlineSession<WhoisModel>(widget.room);

  WhoisModel get m => session.model;
  @override
  bool get ready => session.ready;
  int get me => session.me;

  final _rootKey = GlobalKey(), _boardKey = GlobalKey();

  /// صوتي قبل ما يرجع من السيرفر
  int picked = -1;

  /// وقت بداية كشف الجولة عندي (للحركة)، -10 = ما شفت الكشف يبدي (دخلت بنصه)
  double revealAt = -10;

  /// وقت بداية شاشة الألقاب عندي (-100 = تنعرض كلها مرة وحدة)
  double finalAt = -100;
  int _landedSfx = 0, _lastTick = -1, _rowsShown = -1;
  bool _titleShown = false;
  String _sig = '';
  Size area = Size.zero;
  List<Rect> rects = const [];
  final List<_Bit> bits = [];
  final _rnd = math.Random();

  /// طيران الأصوات: (الهدف، المصدر أو -1 إذا مجهول)
  List<(int, int)> tokens = const [];
  double _stagger = 0.14;
  static const _flight = 0.55;

  @override
  void initState() {
    super.initState();
    Sfx.preload(const ['pop', 'whoosh', 'clack', 'tada', 'tick', 'win']);
    Music.play('music_whois', volume: 0.25);
  }

  @override
  void dispose() {
    Music.stop();
    session.dispose();
    super.dispose();
  }

  @override
  void restart() {
    if (!m.over) return;
    session.again();
  }

  /// وقت وصول آخر صوت (بعدها يطلع اللقب)
  double get _landEnd => tokens.isEmpty ? 0.3 : (tokens.length - 1) * _stagger + _flight + 0.25;
  bool get _titleOn => m.phase == 'reveal' && time - revealAt >= _landEnd;

  int landedOf(int target) {
    if (m.phase != 'reveal') return 0;
    final t = time - revealAt;
    var n = 0;
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].$1 == target && t >= i * _stagger + _flight) n++;
    }
    return n;
  }

  void _buildTokens() {
    final list = <(int, int)>[];
    if (m.showVoters) {
      for (var p = 0; p < m.players; p++) {
        final t = m.votes[p];
        if (t >= 0 && !m.out[p] && !m.out[t]) list.add((t, p));
      }
    } else {
      final rounds = m.tally.fold(0, math.max);
      for (var r = 0; r < rounds; r++) {
        for (var t = 0; t < m.players; t++) {
          if (m.tally[t] > r) list.add((t, -1));
        }
      }
    }
    tokens = list;
    _stagger = list.isEmpty ? 0.14 : math.min(0.14, 2.4 / list.length);
  }

  // ------------------------------------------------------------ الاحتفال

  /// نقطة بالوحة → إحداثيات الشاشة (طبقة القصاصات)
  Offset? _toRoot(Offset boardPt) {
    final b = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    final r = _rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (b == null || r == null || !b.attached || !r.attached) return null;
    return r.globalToLocal(b.localToGlobal(boardPt));
  }

  void _burst(Offset at, {int n = 40, double power = 1}) {
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.2;
      final s = (260 + _rnd.nextDouble() * 360) * power;
      bits.add(_Bit(at, Offset(math.cos(a) * s, math.sin(a) * s), _confettiColors[_rnd.nextInt(_confettiColors.length)], (_rnd.nextDouble() - 0.5) * 14));
    }
    if (bits.length > 260) bits.removeRange(0, bits.length - 260);
  }

  void _stepBits(double dt) {
    for (final b in bits) {
      b.v = Offset(b.v.dx * (1 - 1.2 * dt), b.v.dy + 700 * dt);
      b.p += b.v * dt;
      b.rot += b.spin * dt;
      b.life -= dt;
    }
    bits.removeWhere((b) => b.life <= 0);
  }

  // ------------------------------------------------------------ الألقاب النهائية بالتدريج

  /// الترتيب: الأقل أصوات أول، ونجم اللمّة آخر واحد
  List<int> get _finalOrder {
    final ps = List.of(m.alive)..sort((a, b) => m.total[a].compareTo(m.total[b]));
    final s = m.star;
    if (s >= 0) {
      ps.remove(s);
      ps.add(s);
    }
    return ps;
  }

  double _rowAt(int i) => finalAt + 0.9 + i * 0.8;
  int get _rowsVisible {
    final n = m.alive.length;
    var k = 0;
    while (k < n && time >= _rowAt(k)) {
      k++;
    }
    return k;
  }

  bool get _factsOn => _rowsVisible >= m.alive.length && time >= _rowAt(m.alive.length - 1) + 0.6;

  // ------------------------------------------------------------ الإطار

  @override
  void update(double dt) {
    session.update(dt);
    _stepBits(dt);
    for (final e in session.takeEvents()) {
      switch (e['e']) {
        case 'q':
          picked = -1;
          revealAt = -10;
          _landedSfx = 0;
          _lastTick = -1;
          Sfx.play('whoosh', volume: 0.5);
        case 'voted':
          Sfx.play('clack', volume: 0.25);
        case 'reveal':
          _buildTokens();
          revealAt = time;
          _landedSfx = 0;
        case 'final':
          finalAt = time;
          _rowsShown = 0;
          Music.stop();
          Sfx.play('win');
          Fx.big();
        case 'again':
          finalAt = -100;
          _rowsShown = -1;
          Music.play('music_whois', volume: 0.25);
      }
    }
    if (!ready) return;
    // صوت كل صوت يوصل
    if (m.phase == 'reveal' && revealAt > 0) {
      var n = 0;
      final t = time - revealAt;
      for (var i = 0; i < tokens.length; i++) {
        if (t >= i * _stagger + _flight) n++;
      }
      if (n > _landedSfx) {
        _landedSfx = n;
        Sfx.play('pop', volume: 0.5);
      }
    }
    // تكتكة آخر 5 ثواني لمن ما صوّت
    if (m.phase == 'vote' && me >= 0 && !m.out[me] && _myVote < 0) {
      final left = m.timeLeft.ceil();
      if (left <= 5 && left > 0 && left != _lastTick) {
        _lastTick = left;
        Sfx.play('tick', volume: 0.5);
      }
    }
    // الألقاب النهائية تطلع واحد واحد
    final rows = m.over ? _rowsVisible : -1;
    if (m.over && _rowsShown >= 0 && rows > _rowsShown) {
      _rowsShown = rows;
      final last = rows == m.alive.length && m.star >= 0;
      if (last) {
        Sfx.play('tada');
        Fx.mid();
        final s = MediaQuery.sizeOf(context);
        _burst(Offset(s.width * 0.3, s.height * 0.45), n: 50, power: 1.2);
        _burst(Offset(s.width * 0.7, s.height * 0.45), n: 50, power: 1.2);
      } else {
        Sfx.play('pop', volume: 0.7);
      }
    }
    final sig = '${m.phase}|${m.qi}|${m.votes}|${m.top}|${m.out}|${m.tally}|${m.total}|$_titleOn|${m.timeLeft.ceil()}|$rows|${m.over && _factsOn}';
    if (sig != _sig) {
      _sig = sig;
      if (_titleOn != _titleShown) {
        _titleShown = _titleOn;
        if (_titleShown && m.top.isNotEmpty && revealAt > 0) {
          Sfx.play('tada', volume: 0.8);
          Fx.mid();
          for (final p in m.top) {
            final i = m.alive.indexOf(p);
            if (i < 0 || i >= rects.length) continue;
            final at = _toRoot(rects[i].center);
            if (at != null) _burst(at, n: m.top.length > 2 ? 24 : 40);
          }
        }
      }
      setState(() {});
    }
  }

  void _vote(int p) {
    if (!ready || paused || me < 0 || m.phase != 'vote' || m.out[me] || p == me || m.out[p]) return;
    setState(() => picked = p);
    session.input(me, {'a': 'vote', 't': p});
    Fx.tap();
  }

  int get _myVote => picked >= 0 ? picked : (me >= 0 ? m.votes[me] : -1);

  // ------------------------------------------------------------ الواجهة

  String _name(int p) => p == me ? 'أنت' : session.nameOf(p);
  Color _colorOf(int p) {
    final room = widget.room;
    return C.players[(p < room.seats.length ? room.seats[p] : p) % C.players.length];
  }

  String _avatarOf(int p) {
    final room = widget.room;
    return p < room.seats.length ? room.avatarOfSeat(room.seats[p]) : '';
  }

  String get _status {
    switch (m.phase) {
      case 'count':
        return 'استعدّوا... السؤال الأول قادم';
      case 'vote':
        if (me < 0 || m.out[me]) return 'أنت تتفرّج';
        return _myVote < 0 ? 'اضغط على من تظنّه الأنسب (سرًّا)' : 'تم تسجيل صوتك، ويمكنك تغييره';
      default:
        if (m.top.isEmpty) return 'لا أحد صوّت في هذه الجولة';
        if (!_titleOn) return 'نعدّ الأصوات...';
        return '«${m.current.$2}»: ${m.top.map(_name).join(' و ')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      child: Stack(
        key: _rootKey,
        children: [
          const Positioned.fill(child: _Backdrop()),
          if (!ready)
            const NetWaiting()
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(60, 8, 12, 10),
                child: Column(
                  children: [
                    _header(),
                    const SizedBox(height: 10),
                    Expanded(child: _board()),
                    const SizedBox(height: 6),
                    _statusBox(),
                  ],
                ),
              ),
            ),
          if (ready) NetBanner(session: session, players: m.players),
          if (ready && m.over) Positioned.fill(child: _finalPanel()),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ConfettiPainter(this)))),
        ],
      ),
    );
  }

  Widget _header() {
    final voted = m.alive.where((p) => m.votes[p] != -1).length;
    return Column(
      children: [
        Row(
          children: [
            Text(m.phase == 'count' ? '' : 'السؤال ${m.qi + 1} من ${WhoisModel.questions}', style: body(14, color: C.muted, weight: FontWeight.w700)),
            const Spacer(),
            if (m.phase == 'vote') Text('صوّت $voted من ${m.alive.length}', style: body(14, color: C.muted, weight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: c)),
          child: Text(
            m.phase == 'count' ? 'منو بينا؟' : m.current.$1,
            key: ValueKey('${m.phase == 'count'}${m.qi}'),
            textAlign: TextAlign.center,
            style: display(m.phase == 'count' ? 46 : 34, shadows: [Shadow(color: alpha(C.accent, 0.6), blurRadius: 20)]),
          ),
        ),
        if (m.phase == 'vote') ...[
          const SizedBox(height: 10),
          SizedBox(height: 8, width: 260, child: CustomPaint(painter: _TimerBar(this))),
        ],
      ],
    );
  }

  Widget _statusBox() {
    final big = m.phase == 'reveal' && _titleOn && m.top.isNotEmpty;
    return SizedBox(
      height: 48,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            _status,
            key: ValueKey(_status),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: big ? display(24, color: _gold) : body(17, weight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  /// أماكن البطاقات (نفسها للبطاقات والرسام)
  static const _maxW = 260.0, _maxH = 240.0;

  List<Rect> _layout(Size s, int n) {
    if (n == 0 || s.isEmpty) return const [];
    var bestC = 1;
    var best = -1.0;
    for (var c = 1; c <= n; c++) {
      final rows = (n / c).ceil();
      final sc = math.min(math.min(s.width / c, _maxW), math.min(s.height / rows, _maxH) * 1.05);
      if (sc > best) {
        best = sc;
        bestC = c;
      }
    }
    final rows = (n / bestC).ceil();
    final cw = math.min(s.width / bestC, _maxW), ch = math.min(s.height / rows, _maxH);
    final top = (s.height - ch * rows) / 2;
    final out = <Rect>[];
    for (var i = 0; i < n; i++) {
      final r = i ~/ bestC, c = i % bestC;
      final inRow = r == rows - 1 ? n - r * bestC : bestC;
      final left = (s.width - cw * inRow) / 2 + c * cw;
      out.add(Rect.fromLTWH(left, top + r * ch, cw, ch).deflate(7));
    }
    return out;
  }

  Widget _board() {
    return LayoutBuilder(builder: (context, box) {
      final ps = m.alive;
      area = Size(box.maxWidth, box.maxHeight);
      rects = _layout(area, ps.length);
      return Stack(
        key: _boardKey,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < ps.length; i++) Positioned.fromRect(rect: rects[i], child: _card(ps[i], rects[i])),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FlyPainter(this)))),
        ],
      );
    });
  }

  Widget _card(int p, Rect r) {
    final col = _colorOf(p);
    final mine = p == me;
    final chosen = m.phase == 'vote' && _myVote == p;
    final voted = m.phase == 'vote' && m.votes[p] != -1;
    final isTop = m.phase == 'reveal' && _titleOn && m.top.contains(p);
    // الصورة تاخذ اللي يبقى بعد الاسم والحالة (حتى بالشاشات الصغيرة ما تطلع برا البطاقة)
    final av = math.max(18.0, math.min(r.height - 64, math.min(r.height * 0.5, r.width * 0.56)));
    final canTap = m.phase == 'vote' && me >= 0 && !m.out[me] && !mine;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canTap ? () => _vote(p) : null,
      child: AnimatedScale(
        scale: chosen ? 1.05 : (isTop ? 1.07 : 1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: alpha(col, chosen || isTop ? 0.32 : (mine && m.phase == 'vote' ? 0.06 : 0.15)),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: alpha(isTop ? _gold : col, chosen || isTop ? 1 : 0.45), width: chosen || isTop ? 3.5 : 1.5),
            boxShadow: chosen || isTop ? [BoxShadow(color: alpha(isTop ? _gold : col, 0.45), blurRadius: 22)] : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: av,
                height: av,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: alpha(col, 0.25), shape: BoxShape.circle, border: Border.all(color: col, width: 3)),
                child: Avatar(_avatarOf(p), size: av * 0.72),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(mine ? '${session.nameOf(p)} (أنت)' : session.nameOf(p),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: body(r.width < 120 ? 13 : 16, weight: FontWeight.w800)),
              ),
              SizedBox(
                height: 20,
                child: voted
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF5CE08A)),
                        const SizedBox(width: 3),
                        Text('صوّت', style: body(12, color: const Color(0xFF5CE08A), weight: FontWeight.w700)),
                      ])
                    : (m.phase == 'reveal' && m.votes[p] == -1 && !m.away[p] ? Text('ممتنع', style: body(12, color: C.muted)) : null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ شاشة الألقاب

  String _times(int n) => n == 1 ? 'مرة واحدة' : (n == 2 ? 'مرتين' : '$n مرات');
  String _votes(int n) => n == 0
      ? 'بلا أصوات'
      : n == 1
          ? 'صوت واحد'
          : n == 2
              ? 'صوتان'
              : n <= 10
                  ? '$n أصوات'
                  : '$n صوتًا';

  /// نص الإحصائية المضحكة
  String _factText((String, int, int, int) f) {
    final (k, a, b, n) = f;
    final na = session.nameOf(a);
    switch (k) {
      case 'unan':
        return 'لقب ${whoisBank[b].$2} لـ$na بالإجماع';
      case 'pair':
        return '$na صوّت لـ${session.nameOf(b)} ${_times(n)}!';
      case 'star':
        return 'نجم اللمّة: $na (${_votes(n)})';
      case 'rebel':
        return n == 0 ? '$na المتمرّد: لم يتفق مع الأغلبية ولا مرة' : '$na المتمرّد: اتفق مع الأغلبية ${_times(n)} فقط';
      case 'herd':
        return '$na يفكّر مثل الأغلبية: اتفق معهم ${_times(n)}';
      case 'zero':
        return '$na المظلوم: لم يحصل على أي صوت';
      default:
        return '$na أبو الامتناع: لم يصوّت ${_times(n)}';
    }
  }

  ShareCardData _share() {
    final ps = _finalOrder.reversed.toList();
    if (ps.isEmpty) return ShareCardData(game: 'منو بينا؟', winner: -1, players: const []);
    final idx = math.max(0, ps.indexOf(me));
    final facts = m.facts;
    return ShareCardData(
      game: 'منو بينا؟',
      winner: idx,
      titles: true,
      headline: '«${m.finalTitleOf(ps[idx])}»',
      stat: facts.isEmpty ? null : _factText(facts.first),
      players: [
        for (final p in ps) CardPlayer(session.nameOf(p), _avatarOf(p), _colorOf(p), m.total[p], title: m.finalTitleOf(p)),
      ],
    );
  }

  Widget _finalPanel() {
    final order = _finalOrder;
    final shown = _rowsVisible;
    final star = m.star;
    final done = _factsOn;
    final facts = done ? m.facts.where((f) => f.$1 != 'star').take(3).toList() : const <(String, int, int, int)>[];
    return GestureDetector(
      // ضغطة = تطلع كل الألقاب مرة وحدة
      behavior: HitTestBehavior.opaque,
      onTap: done ? null : () => setState(() => finalAt = time - 100),
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: alpha(const Color(0xFF05070F), 0.86))),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('ألقاب لمّتنا', style: display(42, color: _gold, shadows: [Shadow(color: alpha(_gold, 0.5), blurRadius: 22)])),
                      const SizedBox(height: 10),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            // الأحدث فوق: النجم يطلع بالأعلى آخر شي
                            for (var i = shown - 1; i >= 0; i--) _titleRow(order[i], order[i] == star, key: ValueKey(order[i])),
                          ],
                        ),
                      ),
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final f in facts)
                          _FadeIn(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(_factText(f), textAlign: TextAlign.center, style: body(15, weight: FontWeight.w700, color: const Color(0xFFFFD27A))),
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      if (done)
                        _FadeIn(
                          child: Column(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  BigButton(label: againLabelOf(session) ?? 'العب مرة أخرى', icon: Icons.replay_rounded, onTap: restart),
                                  const SizedBox(width: 10),
                                  BigButton(label: 'الغرفة', filled: false, onTap: roomMenu(context, session) ?? () => Navigator.of(context).pop()),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ShareResultButton(data: _share),
                            ],
                          ),
                        )
                      else
                        Text('اضغط لإظهار الكل', style: body(13, color: C.muted)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleRow(int p, bool isStar, {Key? key}) {
    final col = _colorOf(p);
    return _FadeIn(
      key: key,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: isStar ? 14 : 9),
        decoration: BoxDecoration(
          color: alpha(isStar ? _gold : col, isStar ? 0.22 : (p == me ? 0.26 : 0.14)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: alpha(isStar ? _gold : col, isStar || p == me ? 0.95 : 0.4), width: isStar ? 3 : (p == me ? 2 : 1)),
          boxShadow: isStar ? [BoxShadow(color: alpha(_gold, 0.35), blurRadius: 24)] : null,
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: isStar ? 54 : 42,
                  height: isStar ? 54 : 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: alpha(col, 0.25), shape: BoxShape.circle, border: Border.all(color: col, width: 2)),
                  child: Avatar(_avatarOf(p), size: isStar ? 38 : 28),
                ),
                if (isStar) Positioned(top: -22, child: SizedBox(width: 34, height: 26, child: CustomPaint(painter: CrownPainter(_gold)))),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p == me ? '${session.nameOf(p)} (أنت)' : session.nameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(15, weight: FontWeight.w800)),
                  Text(isStar ? 'نجم اللمّة • ${_votes(m.total[p])}' : _votes(m.total[p]), style: body(12, color: isStar ? _gold : C.muted, weight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(m.finalTitleOf(p), textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(isStar ? 28 : 22, color: _gold)),
            ),
          ],
        ),
      ),
    );
  }
}

/// تطلع بحركة (تكبر وتبان) أول ما تنبني
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.7 + 0.3 * t, child: c),
      ),
      child: child,
    );
  }
}

/// خلفية ثابتة (تنرسم مرة)
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(center: const Alignment(0, -0.5), radius: 1.2, colors: [lighten(kWorld['whois']!, 0.05), darken(kWorld['whois']!, 0.4)]),
      ),
    );
  }
}

/// شريط الوقت
class _TimerBar extends CustomPainter {
  _TimerBar(this.s) : super(repaint: s.frame);
  final _WhoisState s;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(r, Paint()..color = alpha(Colors.white, 0.1));
    final f = (s.m.timeLeft / WhoisModel.voteTime).clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * f, size.height), Radius.circular(size.height / 2)),
      Paint()..color = f < 0.3 ? const Color(0xFFFF4D6A) : _gold,
    );
  }

  @override
  bool shouldRepaint(_TimerBar old) => true;
}

/// الأصوات الطايرة فوق الصور + عدّاد الأصوات + التاج + لافتة اللقب
class _FlyPainter extends CustomPainter {
  _FlyPainter(this.s) : super(repaint: s.frame);
  final _WhoisState s;

  TextPainter _tp(String t, TextStyle st, [double maxW = 400]) => TextPainter(
        text: TextSpan(text: t, style: st),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxW);

  @override
  void paint(Canvas canvas, Size size) {
    final m = s.m;
    if (m.phase != 'reveal') return;
    final ps = m.alive;
    final rects = s.rects;
    if (rects.length != ps.length) return;
    Rect? rectOf(int p) {
      final i = ps.indexOf(p);
      return i < 0 ? null : rects[i];
    }

    final t = s.time - s.revealAt;
    // الأصوات الطايرة
    for (var i = 0; i < s.tokens.length; i++) {
      final k = (t - i * s._stagger) / _WhoisState._flight;
      if (k <= 0 || k >= 1) continue;
      final to = rectOf(s.tokens[i].$1);
      if (to == null) continue;
      final from = s.tokens[i].$2 >= 0 ? (rectOf(s.tokens[i].$2)?.center ?? Offset(size.width / 2, -30)) : Offset(size.width / 2, -30);
      final e = Curves.easeInOut.transform(k);
      final pos = Offset.lerp(from, to.center, e)! - Offset(0, math.sin(e * math.pi) * 50);
      canvas.drawCircle(pos, 12, Paint()..color = alpha(_gold, 0.3));
      canvas.drawCircle(pos, 8, Paint()..color = _gold);
    }
    final titleT = t - s._landEnd;
    for (var i = 0; i < ps.length; i++) {
      final p = ps[i];
      final r = rects[i];
      // العدّاد
      final n = s.landedOf(p);
      if (n > 0) {
        final c = Offset(r.right - 18, r.top + 18);
        canvas.drawCircle(c, 18, Paint()..color = _gold);
        final tp = _tp('$n', display(22, color: const Color(0xFF2B2000)));
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
      if (!s._titleOn || !m.top.contains(p)) continue;
      final k = Curves.easeOutBack.transform((titleT / 0.35).clamp(0.0, 1.0));
      // التاج
      final cw = math.min(r.width * 0.45, 64.0);
      canvas.save();
      canvas.translate(r.center.dx, r.top);
      canvas.scale(k);
      CrownPainter(_gold).paint(canvas..translate(-cw / 2, -cw * 0.62), Size(cw, cw * 0.78));
      canvas.restore();
      // لافتة اللقب تحت البطاقة
      final tp = _tp(m.current.$2, display(r.width < 130 ? 15 : 19, color: const Color(0xFF2B2000)), math.max(80, r.width * 1.3));
      final w = tp.width + 26, h = tp.height + 10;
      canvas.save();
      canvas.translate(r.center.dx, r.bottom - 2);
      canvas.scale(k);
      final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(h / 2));
      canvas.drawRRect(rr.shift(const Offset(0, 3)), Paint()..color = alpha(Colors.black, 0.35));
      canvas.drawRRect(rr, Paint()..color = _gold);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FlyPainter old) => true;
}

/// القصاصات الملونة (فوق كل شي)
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.s) : super(repaint: s.frame);
  final _WhoisState s;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final b in s.bits) {
      paint.color = alpha(b.c, (b.life / 0.6).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(b.p.dx, b.p.dy);
      canvas.rotate(b.rot);
      canvas.drawRect(const Rect.fromLTWH(-5, -3, 10, 6), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}

/// أيقونة اللعبة بالقائمة: ثلاث وجوه وعلامة استفهام
class WhoisIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const cols = [Color(0xFFFF6B6B), Color(0xFFFFD34D), Color(0xFF5CE08A)];
    for (var i = 0; i < 3; i++) {
      final c = Offset(w * (0.22 + i * 0.28), h * 0.72);
      canvas.drawCircle(c, w * 0.12, Paint()..color = cols[i]);
      canvas.drawCircle(c + Offset(-w * 0.04, -h * 0.02), w * 0.015, Paint()..color = Colors.black87);
      canvas.drawCircle(c + Offset(w * 0.04, -h * 0.02), w * 0.015, Paint()..color = Colors.black87);
    }
    final tp = TextPainter(
      text: TextSpan(text: '؟', style: TextStyle(fontSize: h * 0.5, color: Colors.white, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset(w * 0.5 - tp.width / 2, h * 0.3 - tp.height / 2));
  }

  @override
  bool shouldRepaint(WhoisIcon old) => false;
}
