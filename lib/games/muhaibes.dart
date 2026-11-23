import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../logic/muhaibes_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/art.dart';
import '../ui/theme.dart';

/// المحيبس: فريقين، أونلاين/محلي بس (كل واحد بتلفونه). القواعد بـ MuhaibesModel، والسيرفر
/// يخفي مكان المحبس عن الفريق الثاني. فريقي دائماً تحت، والخصم فوق.
class MuhaibesGame extends StatefulWidget {
  const MuhaibesGame({super.key, required this.room});
  final RoomConn room;

  @override
  State<MuhaibesGame> createState() => _MuhaibesState();
}

/// ألوان الفريقين (الأحمر والأزرق)
const _teamColors = [Color(0xFFFF4D6A), Color(0xFF3D8BFF)];
const _teamNames = ['الفريق الأحمر', 'الفريق الأزرق'];
const _gold = Color(0xFFFFD34D);

class _MuhaibesState extends LoopState<MuhaibesGame> {
  late final OnlineSession<MuhaibesModel> session = OnlineSession<MuhaibesModel>(widget.room);

  MuhaibesModel get m => session.model;
  @override
  bool get ready => session.ready;

  int get me => session.me;

  /// فريقي (المتفرج يشوف الأحمر تحت)
  int get myTeam => me >= 0 ? MuhaibesModel.teamOf(me) : 0;

  /// القبضة اللي اخترتها كقائد (قبل طالعة/بات)
  int selected = -1;

  /// وقت آخر تحريك لكل قبضة (للاهتزاز)
  final Map<int, double> shakeAt = {};
  final Map<int, double> openAt = {};
  double revealAt = -10, endAt = 0;
  bool showOver = false;
  String _sig = '';
  int _lastTick = -1;

  @override
  void initState() {
    super.initState();
    Sfx.preload(const ['drum', 'pop', 'whoosh', 'clack', 'gold', 'freeze', 'tick', 'win']);
    Music.play('music_muhaibes', volume: 0.28);
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

  @override
  void update(double dt) {
    session.update(dt);
    for (final e in session.takeEvents()) {
      switch (e['e']) {
        case 'round':
          selected = -1;
          openAt.clear();
          showOver = false;
          Sfx.play('drum');
        case 'hidden':
          Sfx.play('whoosh', volume: 0.6);
        case 'open':
          openAt[e['f'] as int] = time;
          Sfx.play('pop', volume: 0.7);
          Fx.tap();
        case 'shake':
          shakeAt[e['f'] as int] = time;
          Sfx.play('clack', volume: 0.35);
        case 'reveal':
          revealAt = time;
          openAt[e['f'] as int] = time;
          final team = e['team'] as int;
          if (team == myTeam) {
            Sfx.play('gold');
            Fx.mid();
          } else {
            Sfx.play('freeze', volume: 0.7);
            Fx.hit();
          }
        case 'win':
          endAt = time;
          Music.stop();
          Sfx.play('win');
          Fx.big();
      }
    }
    if (!ready) return;
    // نعيد بناء الواجهة بس لمّن تتغير الحالة (السيرفر يدز 4 مرات بالثانية)
    final sig = '${m.phase}|${m.opened}|${m.ring}|${m.aim}|${m.hider}|${m.leader}|${m.teamScore}|${m.out}|${m.holding}|${m.over}';
    if (sig != _sig) {
      _sig = sig;
      if (m.phase != 'guess' || !m.closedFists.contains(selected)) selected = -1;
      setState(() {});
    }
    // تكتكة آخر 5 ثواني لمن عليه الدور
    final left = m.timeLeft.ceil();
    final mine = (m.phase == 'hide' && me == m.hider) || (m.phase == 'guess' && me == m.leader);
    if (mine && left <= 5 && left > 0 && left != _lastTick) {
      _lastTick = left;
      Sfx.play('tick', volume: 0.5);
    }
    final shouldShow = m.over && time - endAt > 2.2;
    if (shouldShow != showOver) setState(() => showOver = shouldShow);
  }

  // ------------------------------------------------------------ الحركات

  void _tapFist(int f) {
    if (!ready || m.over || paused || me < 0) return;
    final owner = MuhaibesModel.ownerOf(f);
    final ownTeam = MuhaibesModel.teamOf(owner) == m.holding;
    if (m.phase == 'hide' && me == m.hider && ownTeam) {
      session.input(me, {'a': 'hide', 'f': f});
      Fx.tap();
      return;
    }
    if (m.phase == 'guess' && me == m.leader && ownTeam && !m.opened[f]) {
      setState(() => selected = f);
      session.input(me, {'a': 'aim', 'f': f});
      Fx.tap();
      return;
    }
    // الفريق المخبّي يحرّك قبضاته للتضليل
    if (MuhaibesModel.teamOf(me) == m.holding && ownTeam && !m.opened[f] && m.phase != 'reveal') {
      session.input(me, {'a': 'shake', 'f': f});
    }
  }

  void _act(String a) {
    if (selected < 0) return;
    session.input(me, {'a': a, 'f': selected});
    Fx.mid();
    setState(() => selected = -1);
  }

  // ------------------------------------------------------------ الواجهة

  String _name(int p) => p == me ? 'أنت' : session.nameOf(p);

  String get _status {
    if (m.over) return 'فاز ${_teamNames[m.winTeam]}!';
    switch (m.phase) {
      case 'hide':
        if (me == m.hider) return 'اختر القبضة التي تخبّئ فيها المحبس';
        if (me >= 0 && myTeam == m.holding) return '${_name(m.hider)} يخبّئ المحبس... حرّك قبضاتك للتمويه';
        return '${_name(m.hider)} يخبّئ المحبس...';
      case 'guess':
        if (me == m.leader) return selected < 0 ? 'اختر قبضة من قبضات الخصم' : 'طالعة أم بات؟';
        if (me >= 0 && myTeam == m.holding) return '${_name(m.leader)} يبحث عن المحبس... اضغط قبضاتك لتحريكها';
        return '${_name(m.leader)} يبحث عن المحبس';
      default:
        final who = _teamNames[m.lastTeam];
        final pts = '+${m.lastPts} ل$who';
        if (m.lastAct == 'bat') {
          return m.lastTeam != m.holding ? 'بات صحيحة! $pts' : 'بات خاطئة! $pts';
        }
        return 'المحبس في القبضة! $pts';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      child: Stack(
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
                    _scoreBar(),
                    const SizedBox(height: 8),
                    Expanded(child: _teamArea(1 - myTeam)),
                    _statusBox(),
                    Expanded(child: _teamArea(myTeam)),
                    _actionBar(),
                  ],
                ),
              ),
            ),
          if (ready) NetBanner(session: session, players: m.players),
          if (showOver)
            Positioned.fill(
              child: ResultOverlay(
                winner: m.winTeam,
                scores: m.teamScore,
                seats: const [0, 1],
                names: _teamNames,
                menuLabel: 'الغرفة',
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

  Widget _scoreBar() {
    Widget side(int t) {
      final c = _teamColors[t];
      final mine = me >= 0 && t == myTeam;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: alpha(c, t == m.holding ? 0.26 : 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: alpha(c, t == m.holding ? 0.9 : 0.4), width: t == m.holding ? 2 : 1),
          ),
          child: Row(
            children: [
              if (t == m.holding) ...[
                const SizedBox(width: 18, height: 18, child: CustomPaint(painter: _RingIcon())),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(mine ? 'فريقك' : _teamNames[t],
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w800)),
              ),
              Text('${m.teamScore[t]}', style: display(28, color: c)),
              Text(' / ${MuhaibesModel.target}', style: body(12, color: C.muted)),
            ],
          ),
        ),
      );
    }

    return Row(children: [side(myTeam), const SizedBox(width: 8), side(1 - myTeam)]);
  }

  Widget _statusBox() {
    final timed = m.phase != 'reveal' && !m.over;
    final total = m.phase == 'hide' ? MuhaibesModel.hideTime : MuhaibesModel.moveTime;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text(_status, textAlign: TextAlign.center, style: body(17, weight: FontWeight.w800)),
          if (timed) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 6,
              width: 220,
              child: CustomPaint(painter: _TimerBar(this, total)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _teamArea(int team) {
    final ps = [for (var p = team; p < m.players; p += 2) if (!m.out[p]) p];
    final c = _teamColors[team];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: alpha(c, 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: alpha(c, 0.25)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / math.max(1, ps.length);
        // قبضتين بالعرض (ويا المسافات) لازم يكفّن حتى بـ8 لاعبين على تلفون صغير
        final fist = (math.min(w / 2.3, box.maxHeight * 0.42)).clamp(16.0, 72.0);
        return Row(
          children: [
            for (final p in ps) Expanded(child: _playerCard(p, fist)),
          ],
        );
      }),
    );
  }

  Widget _playerCard(int p, double fist) {
    final room = widget.room;
    final seat = p < room.seats.length ? room.seats[p] : p;
    final col = C.players[seat % C.players.length];
    final role = p == m.hider && m.phase == 'hide'
        ? 'يخبّئ'
        : p == m.leader && m.phase == 'guess'
            ? 'القائد'
            : null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: alpha(col, 0.25), shape: BoxShape.circle, border: Border.all(color: col, width: 2)),
          child: Avatar(room.avatarOfSeat(seat), size: 24),
        ),
        const SizedBox(height: 2),
        Text(_name(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12, weight: FontWeight.w700)),
        SizedBox(
          height: 16,
          child: role == null ? null : Text(role, style: body(11, weight: FontWeight.w800, color: _gold)),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var h = 0; h < 2; h++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: fist * 0.06),
                child: _fist(p * 2 + h, fist, col),
              ),
          ],
        ),
      ],
    );
  }

  Widget _fist(int f, double size, Color sleeve) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapFist(f),
      child: SizedBox(
        width: size,
        height: size * 1.2,
        child: CustomPaint(painter: _FistPainter(this, f, sleeve)),
      ),
    );
  }

  Widget _actionBar() {
    final show = m.phase == 'guess' && me == m.leader && selected >= 0 && !m.over;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: BigButton(label: 'طالعة', icon: Icons.back_hand_rounded, filled: false, onTap: () => _act('open')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BigButton(label: 'بات', icon: Icons.touch_app_rounded, color: _gold, onTap: () => _act('bat')),
                  ),
                ],
              ),
            ),
    );
  }
}

/// خلفية دافية ثابتة (تنرسم مرة)
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(center: const Alignment(0, -0.2), radius: 1.1, colors: [lighten(kWorld['muhaibes']!, 0.08), darken(kWorld['muhaibes']!, 0.4)]),
      ),
    );
  }
}

/// شريط الوقت (يتحدث كل إطار بدون إعادة بناء الواجهة)
class _TimerBar extends CustomPainter {
  _TimerBar(this.s, this.total) : super(repaint: s.frame);
  final _MuhaibesState s;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(r, Paint()..color = alpha(Colors.white, 0.1));
    final f = (s.m.timeLeft / total).clamp(0.0, 1.0);
    final c = f < 0.3 ? const Color(0xFFFF4D6A) : _gold;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * f, size.height), Radius.circular(size.height / 2)),
      Paint()..color = c,
    );
  }

  @override
  bool shouldRepaint(_TimerBar old) => true;
}

/// أيقونة المحبس الصغيرة
class _RingIcon extends CustomPainter {
  const _RingIcon();

  @override
  void paint(Canvas canvas, Size size) => _paintRing(canvas, size.center(Offset.zero), size.shortestSide * 0.36);

  @override
  bool shouldRepaint(_RingIcon old) => false;
}

/// خاتم ذهبي بفص
void _paintRing(Canvas canvas, Offset c, double r) {
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.42
      ..color = _gold,
  );
  canvas.drawCircle(c - Offset(r * 0.25, r * 0.25), r * 0.18, Paint()..color = alpha(Colors.white, 0.8));
  canvas.drawCircle(c + Offset(0, -r * 1.05), r * 0.34, Paint()..color = const Color(0xFFE23A5A));
}

/// قبضة (مسكّرة أو مفتوحة) مرسومة بالكود. تهتز إذا حرّكها الفريق المخبّي.
class _FistPainter extends CustomPainter {
  _FistPainter(this.s, this.f, this.sleeve) : super(repaint: s.frame);
  final _MuhaibesState s;
  final int f;
  final Color sleeve;

  static const _skin = Color(0xFFE8B48A);
  static const _skinDark = Color(0xFFB97F57);

  @override
  void paint(Canvas canvas, Size size) {
    final m = s.m;
    final w = size.width, h = size.height;
    final open = m.opened[f] || (m.phase == 'reveal' && m.lastFist == f);
    final mine = MuhaibesModel.teamOf(MuhaibesModel.ownerOf(f)) == m.holding;
    final hasRing = m.ring == f;

    // اهتزاز
    final st = s.time - (s.shakeAt[f] ?? -10);
    final dx = st < 0.45 ? math.sin(st * 42) * w * 0.09 * (1 - st / 0.45) : 0.0;
    canvas.save();
    canvas.translate(dx, 0);

    // تحديد: القائد يباوع عليها (الكل يشوف)، أو اخترتها أنا
    final aimed = m.phase == 'guess' && (m.aim == f || s.selected == f);
    if (aimed) {
      final pulse = 0.6 + 0.4 * math.sin(s.time * 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-w * 0.04, h * 0.02, w * 1.08, h * 0.96), Radius.circular(w * 0.3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = alpha(_gold, pulse),
      );
    }
    // المخبّي يختار: قبضات فريقه تلمع
    final choosing = m.phase == 'hide' && s.me == m.hider && mine;
    if (choosing) {
      canvas.drawCircle(Offset(w / 2, h * 0.5), w * 0.62, Paint()..color = alpha(_gold, 0.12 + 0.08 * math.sin(s.time * 5)));
    }

    // الكم بلون اللاعب
    final cuff = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.2, h * 0.8, w * 0.6, h * 0.2), Radius.circular(w * 0.08));
    canvas.drawRRect(cuff, Paint()..color = sleeve);

    final fill = Paint()..color = _skin;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.035)
      ..color = _skinDark;

    if (!open) {
      // قبضة مسكّرة: كف مدوّر + أربع مفاصل + إبهام
      final palm = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.08, h * 0.22, w * 0.84, h * 0.6), Radius.circular(w * 0.26));
      canvas.drawRRect(palm, fill);
      canvas.drawRRect(palm, edge);
      for (var i = 0; i < 4; i++) {
        final c = Offset(w * (0.2 + i * 0.2), h * 0.28);
        canvas.drawCircle(c, w * 0.12, fill);
        canvas.drawCircle(c, w * 0.12, edge);
      }
      final thumb = Path()
        ..moveTo(w * 0.14, h * 0.55)
        ..quadraticBezierTo(w * 0.5, h * 0.42, w * 0.7, h * 0.52);
      canvas.drawPath(thumb, edge..strokeWidth = math.max(1.5, w * 0.05));
      // فريقي يعرف وين المحبس: لمعة ذهبية صغيرة
      if (hasRing && m.phase != 'reveal') {
        canvas.drawCircle(Offset(w * 0.5, h * 0.66), w * 0.13, Paint()..color = alpha(_gold, 0.35));
        _paintRing(canvas, Offset(w * 0.5, h * 0.66), w * 0.07);
      }
    } else {
      // قبضة مفتوحة: كف وأصابع
      final t = (s.time - (s.openAt[f] ?? -10)).clamp(0.0, 0.25) / 0.25;
      final spread = 0.6 + 0.4 * t;
      final palm = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.14, h * 0.42, w * 0.72, h * 0.42), Radius.circular(w * 0.22));
      for (var i = 0; i < 4; i++) {
        final x = w * (0.24 + i * 0.17 * spread + (1 - spread) * 0.1);
        final finger = RRect.fromRectAndRadius(Rect.fromLTWH(x - w * 0.07, h * (0.12 + (i == 0 || i == 3 ? 0.06 : 0)), w * 0.14, h * 0.4), Radius.circular(w * 0.07));
        canvas.drawRRect(finger, fill);
        canvas.drawRRect(finger, edge);
      }
      final thumb = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.0, h * 0.5, w * 0.3, h * 0.14), Radius.circular(w * 0.07));
      canvas.drawRRect(thumb, fill);
      canvas.drawRRect(thumb, edge);
      canvas.drawRRect(palm, fill);
      canvas.drawRRect(palm, edge);
      final revealed = m.phase == 'reveal' && m.ring == f;
      if (revealed) {
        canvas.drawCircle(Offset(w * 0.5, h * 0.62), w * 0.3, Paint()..color = alpha(_gold, 0.3));
        _paintRing(canvas, Offset(w * 0.5, h * 0.62), w * 0.13);
      } else if (m.opened[f]) {
        // طالعة: فارغة، نعتّمها شوية
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, h * 0.1, w, h * 0.8), Radius.circular(w * 0.2)),
          Paint()..color = alpha(C.bg, 0.35),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FistPainter old) => true;
}

/// أيقونة اللعبة بالقائمة: قبضتين ومحبس
class MuhaibesIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fill = Paint()..color = const Color(0xFFE8B48A);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..color = const Color(0xFFB97F57);
    for (final x in [0.08, 0.52]) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(w * x, h * 0.3, w * 0.4, h * 0.42), Radius.circular(w * 0.12));
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, edge);
      for (var i = 0; i < 4; i++) {
        canvas.drawCircle(Offset(w * (x + 0.06 + i * 0.093), h * 0.33), w * 0.055, fill);
      }
    }
    _paintRing(canvas, Offset(w * 0.5, h * 0.18), w * 0.08);
  }

  @override
  bool shouldRepaint(MuhaibesIcon old) => false;
}
