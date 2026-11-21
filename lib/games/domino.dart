import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../logic/domino_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/theme.dart';

/// الدومينو: 2 أو 4 لاعبين. القواعد بـ DominoModel (نفسها بالسيرفر، والسيرفر يخفي قطع الخصم).
/// على نفس الجهاز: "مرّر التلفون" ويا شاشة إخفاء بين الأدوار.
class DominoGame extends StatefulWidget {
  const DominoGame({super.key, this.players = 2, this.long = false, this.room});
  final int players;

  /// الهدف 100 بدل 50
  final bool long;
  final RoomConn? room;

  @override
  State<DominoGame> createState() => _DominoState();
}

const _felt = Color(0xFF0E4D3A);
const _gold = Color(0xFFFFD34D);

class _DominoState extends LoopState<DominoGame> {
  late final Session<DominoModel> session = widget.room != null
      ? OnlineSession<DominoModel>(widget.room!)
      : LocalSession(DominoModel(players: widget.players, crazy: widget.long, seed: DateTime.now().microsecondsSinceEpoch));

  DominoModel get m => session.model;
  @override
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;
  bool get online => session.online;

  /// اللاعب اللي نعرض يده تحت: أونلاين آني، على نفس الجهاز اللي دوره
  int get vp => online ? session.me : m.turn;

  /// على نفس الجهاز: آخر لاعب ضغط "أنا جاهز" (حتى ما يشوف قطع غيره)
  int _readyFor = -1;
  bool get covered => !online && m.phase == 'play' && !m.over && _readyFor != m.turn;

  int selected = -1;
  double endAt = 0;
  bool showOver = false;
  String _sig = '';
  int _lastTick = -1;

  /// يتغير لمّن السلسلة تتغير (حتى الطاولة ما تنرسم كل إطار)
  final ValueNotifier<int> boardVer = ValueNotifier(0);
  _Layout? layout;

  /// قطعة نازلة على الطاولة (حركة من مكان اللاعب لمكانها بالسلسلة)
  int flyTile = -1, flyFrom = 0;
  double flyAt = -10;
  static const flyDur = 0.38;

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
    Sfx.preload(const ['clack', 'pop', 'tick', 'gold', 'freeze', 'win', 'whoosh']);
  }

  @override
  void dispose() {
    boardVer.dispose();
    session.dispose();
    super.dispose();
  }

  @override
  void restart() {
    if (online && !m.over) return;
    _readyFor = -1;
    session.again();
  }

  @override
  void update(double dt) {
    // على نفس الجهاز: الوقت يوقف وهو يسلّم التلفون
    if (!covered) session.update(dt);
    for (final e in session.takeEvents()) {
      switch (e['e']) {
        case 'play':
          // القطعة تنزل من مكان اللاعب، والصوت لمّن توصل
          flyTile = e['t'] as int;
          flyFrom = rel(e['p'] as int);
          flyAt = time;
          Sfx.play('whoosh', volume: 0.35);
        case 'draw':
          Sfx.play('pop', volume: 0.6);
          _bubble(e['p'] as int, 'سحب ${e['n']}');
        case 'pass':
          Sfx.play('tick', volume: 0.6);
          _bubble(e['p'] as int, 'مرّر!');
        case 'round':
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
    // وصلت القطعة: تنرسم بالطاولة
    if (flyTile >= 0 && time - flyAt >= flyDur) {
      flyTile = -1;
      boardVer.value++;
      Sfx.play('clack');
      Fx.hit();
    }
    if (bubbles.isNotEmpty && time - bubbles.first.at > bubbleDur) {
      bubbles.removeWhere((b) => time - b.at > bubbleDur);
      setState(() {});
    }
    if (!ready) return;
    final sig = '${m.chain.length}|${m.turn}|${m.phase}|${m.hands.map((h) => h.length)}|${m.side}|${m.over}|${m.pile.length}|${m.round}';
    if (sig != _sig) {
      final chainChanged = _sig.split('|').first != '${m.chain.length}' || m.chain.isEmpty;
      _sig = sig;
      if (chainChanged) boardVer.value++;
      selected = -1;
      setState(() {});
    }
    final left = m.timeLeft.ceil();
    final myTurn = m.phase == 'play' && m.turn == vp && !covered;
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

  bool get myTurn => ready && !m.over && m.phase == 'play' && vp >= 0 && m.turn == vp && !covered && !paused;

  void _tapTile(int t) {
    if (!myTurn) return;
    final sides = m.sidesFor(t);
    if (sides.isEmpty) return;
    if (sides.length == 1 || m.leftEnd == m.rightEnd && m.chainLen == 1) {
      _play(t, sides.first);
    } else {
      setState(() => selected = selected == t ? -1 : t);
      Fx.tap();
    }
  }

  void _play(int t, String s) {
    session.input(vp, {'a': 'play', 't': t, 's': s});
    setState(() => selected = -1);
  }

  void _tapBoard(TapUpDetails d) {
    final l = layout;
    if (selected < 0 || l == null) return;
    final p = d.localPosition;
    final dl = (p - l.leftMark).distance, dr = (p - l.rightMark).distance;
    final lim = l.u * 1.6;
    if (dl < lim && dl <= dr) {
      _play(selected, 'l');
    } else if (dr < lim) {
      _play(selected, 'r');
    }
  }

  // ------------------------------------------------------------ الواجهة

  String nameOf(int p) {
    if (!online) return C.playerNames[p];
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
    if (online && session.me >= 0 && m.sideOf(session.me) == s) return 'فريقك';
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
      if (!m.canMove(vp)) return m.pile.isNotEmpty ? 'لا توجد قطعة مناسبة، اسحب' : 'لا توجد قطعة مناسبة، تمرير...';
      return selected >= 0 ? 'اختر طرف السلسلة' : 'دورك';
    }
    return 'دور ${nameOf(m.turn)}';
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      child: Stack(
        children: [
          const Positioned.fill(child: _Felt()),
          if (!ready)
            const NetWaiting()
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(60, 8, 10, 8),
                child: Column(
                  children: [
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
                    _statusRow(),
                    const SizedBox(height: 6),
                    _hand(),
                  ],
                ),
              ),
            ),
          if (ready) for (final b in bubbles) _bubbleView(b),
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
                  : Text(avatar, style: const TextStyle(fontSize: 20)),
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
    return Column(
      children: [
        _seatLabel(p),
        const SizedBox(height: 4),
        _miniHand(p),
      ],
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
        behavior: HitTestBehavior.opaque,
        onTapUp: _tapBoard,
        child: Stack(
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

  /// كومة السحب ويا عددها
  Widget _stock() {
    final n = m.pile.length;
    return Opacity(
      opacity: n == 0 ? 0.45 : 1,
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
          Text(n == 0 ? 'خلص السحب' : 'السحب $n', style: body(11, weight: FontWeight.w800, color: alpha(Colors.white, 0.85))),
        ],
      ),
    );
  }

  Widget _statusRow() {
    final timed = m.phase == 'play' && !m.over;
    final canDraw = myTurn && !m.canMove(vp) && m.pile.isNotEmpty;
    return Column(
      children: [
        Text(_status, textAlign: TextAlign.center, style: body(16, weight: FontWeight.w800)),
        if (timed) ...[
          const SizedBox(height: 4),
          SizedBox(height: 5, width: 200, child: CustomPaint(painter: _TimerBar(this))),
        ],
        if (canDraw) ...[
          const SizedBox(height: 6),
          BigButton(label: 'اسحب', icon: Icons.add_rounded, color: _gold, onTap: () => session.input(vp, {'a': 'draw'})),
        ],
      ],
    );
  }

  Widget _hand() {
    if (vp < 0) return const SizedBox(height: 8);
    if (covered) return const SizedBox(height: 78);
    final h = m.hands[vp];
    final mine = myTurn;
    final ok = mine ? m.playable(vp).toSet() : const <int>{};
    return SizedBox(
      height: 78,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in h)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => _tapTile(t),
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 150),
                      offset: Offset(0, selected == t ? -0.15 : 0),
                      child: SizedBox(
                        width: 34,
                        height: 68,
                        child: CustomPaint(
                          painter: _TilePainter(t, glow: ok.contains(t), dim: mine && !ok.contains(t)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
    final f = (s.m.timeLeft / DominoModel.turnTime).clamp(0.0, 1.0);
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
void paintTile(Canvas canvas, Rect r, int a, int b, {bool faceDown = false, bool glow = false, bool dim = false}) {
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
  if (glow) {
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
  _TilePainter(this.t, {this.faceDown = false, this.glow = false, this.dim = false});
  final int t;
  final bool faceDown, glow, dim;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t < 0 ? 0 : DominoModel.tileA[t], b = t < 0 ? 0 : DominoModel.tileB[t];
    paintTile(canvas, Offset.zero & size, a, b, faceDown: faceDown || t < 0, glow: glow, dim: dim);
  }

  @override
  bool shouldRepaint(_TilePainter old) => old.t != t || old.glow != glow || old.dim != dim || old.faceDown != faceDown;
}

/// قطعة بمكانها على الطاولة
class _Placed {
  _Placed(this.rect, this.a, this.b, [this.t = -1]);
  final Rect rect;
  final int a, b;

  /// رقم القطعة (حتى نعرف وين نزلت القطعة الأخيرة)
  final int t;
}

class _Layout {
  _Layout(this.tiles, this.u, this.leftMark, this.rightMark);
  final List<_Placed> tiles;
  final double u;
  final Offset leftMark, rightMark;
}

/// السلسلة تتمدد من أول قطعة للجهتين، وإذا وصلت الحافة تلف (مثل الأفعى)
_Layout layoutChain(DominoModel m, Size size) {
  final n = m.chainLen;
  // حجم القطعة: حتى بالطاولة الضيقة (أربعة لاعبين) يصف 4-5 قطع بالصف
  var u = math.min(math.min(size.width / 11, size.height / 7), 28.0);
  if (n == 0) {
    final c = size.center(Offset.zero);
    return _Layout(const [], u, c, c);
  }
  for (var tries = 0; tries < 30; tries++) {
    final tiles = <_Placed>[];
    final margin = u * 0.6;
    final cx = size.width / 2;
    // أول قطعة بالنص
    final a0 = m.chainL(m.anchor), b0 = m.chainR(m.anchor);
    final dbl0 = a0 == b0;
    final r0 = dbl0 ? Rect.fromCenter(center: Offset(cx, 0), width: u, height: 2 * u) : Rect.fromCenter(center: Offset(cx, 0), width: 2 * u, height: u);
    tiles.add(_Placed(r0, a0, b0, m.chainTile(m.anchor)));

    Offset walk(int from, int to, int step, int dir0, int vdir) {
      var x = dir0 > 0 ? r0.right : r0.left;
      var y = 0.0;
      var dir = dir0;
      // نص ارتفاع آخر قطعة بالصف (المزدوجة أطول) حتى اللفّة ما تركب عليها
      var lastHalf = dbl0 ? u : u / 2;
      for (var i = from; i != to; i += step) {
        // a = الرقم القريب من أول قطعة، b = البعيد
        final a = step > 0 ? m.chainL(i) : m.chainR(i);
        final b = step > 0 ? m.chainR(i) : m.chainL(i);
        final dbl = a == b;
        final w = dbl ? u : 2 * u;
        final tid = m.chainTile(i);
        final fits = dir > 0 ? x + w <= size.width - margin : x - w >= margin;
        if (fits) {
          final r = dbl
              ? Rect.fromLTWH(dir > 0 ? x : x - u, y - u, u, 2 * u)
              : Rect.fromLTWH(dir > 0 ? x : x - 2 * u, y - u / 2, 2 * u, u);
          // الأفقية: النص القريب بجهة القطعة اللي قبلها
          tiles.add(dir > 0 || dbl ? _Placed(r, a, b, tid) : _Placed(r, b, a, tid));
          x += dir * w;
          lastHalf = dbl ? u : u / 2;
        } else {
          // لفّة: قطعة عمودية نازلة (أو صاعدة) تحت/فوق طرف آخر قطعة، والصف الجاي يرجع بالعكس
          final left = dir > 0 ? x - u : x;
          final r = vdir > 0 ? Rect.fromLTWH(left, y + lastHalf, u, 2 * u) : Rect.fromLTWH(left, y - lastHalf - 2 * u, u, 2 * u);
          tiles.add(vdir > 0 ? _Placed(r, a, b, tid) : _Placed(r, b, a, tid));
          // الصف الجاي بمستوى النص البعيد من القطعة العمودية
          y += vdir * (lastHalf + 1.5 * u);
          x = dir > 0 ? left : left + u;
          dir = -dir;
          lastHalf = u / 2;
        }
      }
      // مكان علامة الطرف (وين تنحط القطعة الجاية)
      return Offset((x + dir * u * 0.9).clamp(u, size.width - u), y);
    }

    final rightMark = walk(m.anchor + 1, n, 1, 1, 1);
    final leftMark = walk(m.anchor - 1, -1, -1, -1, -1);
    var top = double.infinity, bottom = -double.infinity;
    for (final t in tiles) {
      top = math.min(top, t.rect.top);
      bottom = math.max(bottom, t.rect.bottom);
    }
    top = math.min(top, math.min(leftMark.dy, rightMark.dy) - u);
    bottom = math.max(bottom, math.max(leftMark.dy, rightMark.dy) + u);
    if (bottom - top <= size.height - 8 || tries == 29) {
      final dy = size.height / 2 - (top + bottom) / 2;
      final shift = Offset(0, dy);
      return _Layout([for (final t in tiles) _Placed(t.rect.shift(shift), t.a, t.b, t.t)], u, leftMark + shift, rightMark + shift);
    }
    u *= 0.88;
  }
  throw StateError('layout');
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.s) : super(repaint: s.boardVer);
  final _DominoState s;

  @override
  void paint(Canvas canvas, Size size) {
    final l = layoutChain(s.m, size);
    s.layout = l;
    for (final t in l.tiles) {
      if (t.t >= 0 && t.t == s.flyTile) continue; // بعدها نازلة (_FlyPainter)
      paintTile(canvas, t.rect, t.a, t.b);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}

/// علامتين على طرفي السلسلة لمّن القطعة تنفع للجهتين
class _MarksPainter extends CustomPainter {
  _MarksPainter(this.s) : super(repaint: s.frame);
  final _DominoState s;

  @override
  void paint(Canvas canvas, Size size) {
    final l = s.layout;
    final m = s.m;
    if (l == null || m.chainLen == 0 || s.vp < 0) return;
    final pulse = 0.5 + 0.5 * math.sin(s.time * 6);
    // بدون اختيار: نلوّن بالأخضر الجهات اللي تنفع لأي قطعة عندي
    if (s.selected < 0) {
      final sides = {for (final t in m.playable(s.vp)) ...m.sidesFor(t)};
      for (final side in sides) {
        final p = side == 'l' ? l.leftMark : l.rightMark;
        canvas.drawCircle(p, l.u * 0.7, Paint()..color = alpha(C.go, 0.18 + 0.12 * pulse));
        canvas.drawCircle(
          p,
          l.u * 0.7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = alpha(C.go, 0.7),
        );
      }
      return;
    }
    // قطعة مختارة: علامات ذهبية بس على الجهات اللي تنفع إلها (تنضغط)
    final ok = m.sidesFor(s.selected);
    for (final p in [if (ok.contains('l')) l.leftMark, if (ok.contains('r')) l.rightMark]) {
      canvas.drawCircle(p, l.u * (0.75 + 0.1 * pulse), Paint()..color = alpha(_gold, 0.25 + 0.2 * pulse));
      canvas.drawCircle(
        p,
        l.u * 0.75,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _gold,
      );
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => true;
}

/// القطعة النازلة: تطير من مكان اللاعب لمكانها بالسلسلة وتكبر شوية وترجع
class _FlyPainter extends CustomPainter {
  _FlyPainter(this.s) : super(repaint: s.frame);
  final _DominoState s;

  @override
  void paint(Canvas canvas, Size size) {
    final l = s.layout;
    if (s.flyTile < 0 || l == null) return;
    _Placed? dest;
    for (final t in l.tiles) {
      if (t.t == s.flyTile) dest = t;
    }
    if (dest == null) return;
    final k = ((s.time - s.flyAt) / _DominoState.flyDur).clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(k);
    final r = s.flyFrom;
    final from = r == 0
        ? Offset(size.width / 2, size.height + l.u * 3)
        : s.isTop(r)
            ? Offset(size.width / 2, -l.u * 3)
            : r == 1
                ? Offset(-l.u * 3, size.height / 2)
                : Offset(size.width + l.u * 3, size.height / 2);
    final c = Offset.lerp(from, dest.rect.center, e)!;
    final scale = 1.35 - 0.35 * e;
    final rect = Rect.fromCenter(center: c, width: dest.rect.width * scale, height: dest.rect.height * scale);
    paintTile(canvas, rect, dest.a, dest.b, glow: k < 1);
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
