import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fit.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../logic/hockey_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/theme.dart';

/// هوكي الهواء: لاعبين. القواعد والفيزياء بـ HockeyModel (نفسها بالسيرفر).
/// الطاولة تتكيف ويا حجم الشاشة (تلفون، ايباد، لابتوب) بنفس الشكل.
class HockeyGame extends StatefulWidget {
  const HockeyGame({super.key, this.room});
  final RoomConn? room;

  @override
  State<HockeyGame> createState() => _HockeyState();
}

class _HockeyState extends LoopState<HockeyGame> {
  late final Session<HockeyModel> session = widget.room != null
      ? OnlineSession<HockeyModel>(widget.room!)
      : LocalSession(HockeyModel(players: 2, crazy: false, seed: DateTime.now().microsecondsSinceEpoch));

  HockeyModel get m => session.model;
  @override
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;
  bool get online => session.online;

  /// أونلاين: اللاعب الثاني تنقلب الطاولة حتى يكون تحت
  bool get flipped => online && session.me == 1;

  Size size = Size.zero;
  Rect table = Rect.zero;
  double tw = 1; // عرض الطاولة بالبكسل (= وحدة 1)

  double get rp => HockeyModel.rp * tw;
  double get rk => HockeyModel.rk * tw;
  double get gw => HockeyModel.gw * tw;

  // اللمس (إحداثيات منطقية)
  final owners = <int, int>{};
  final fingerX = [0.0, 0.0], fingerY = [0.0, 0.0];
  final grabX = [0.0, 0.0], grabY = [0.0, 0.0];
  final active = [false, false];
  final targetX = [0.0, 0.0], targetY = [0.0, 0.0];
  double _lastSend = 0;
  double _sentX = -9, _sentY = -9;

  final trail = <Offset>[];
  double hitFlash = 0, goalAt = -10, endAt = 0;
  int lastScorer = -1;
  bool showOver = false;

  GamePhase get phase => !ready || m.counting ? GamePhase.countdown : (showOver ? GamePhase.over : GamePhase.play);
  int get bottomP => flipped ? 1 : 0;

  Offset toScreen(double x, double y) {
    final fx = flipped ? 1 - x : x, fy = flipped ? HockeyModel.h - y : y;
    return Offset(table.left + fx * tw, table.top + fy * tw);
  }

  Offset toLogic(Offset s) {
    var x = (s.dx - table.left) / tw, y = (s.dy - table.top) / tw;
    if (flipped) {
      x = 1 - x;
      y = HockeyModel.h - y;
    }
    return Offset(x, y);
  }

  Offset puckPos() => toScreen(session.lerp((m) => m.puckX), session.lerp((m) => m.puckY));

  Offset padPos(int p) {
    // أونلاين: مضربي يتبع إصبعي مباشرة (بدون انتظار السيرفر)
    if (online && p == session.me && active[p]) return toScreen(m.cx(targetX[p]), m.cy(p, targetY[p]));
    return toScreen(session.lerp((m) => m.padX[p]), session.lerp((m) => m.padY[p]));
  }

  void _layout(Size s) {
    if (s.width <= 0 || s.height <= 0) return;
    size = s;
    // طاولة بنسبة ثابتة: الكل يشوف نفس الملعب مهما كان حجم الشاشة
    table = fitField(s, 1 / HockeyModel.h, margin: 6);
    tw = table.width;
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  void restart() {
    if (online && !m.over) return;
    session.again();
  }

  int _playerOf(Offset local) {
    if (online) return session.me;
    return local.dy > table.center.dy ? 0 : 1;
  }

  void _send(int p, {bool force = false}) {
    final x = targetX[p], y = targetY[p];
    if (!online) {
      session.input(p, {'m': 'pad', 'x': x, 'y': y});
      return;
    }
    if (!force && (time - _lastSend < 0.033 || (x - _sentX).abs() + (y - _sentY).abs() < 0.002)) return;
    _lastSend = time;
    _sentX = x;
    _sentY = y;
    session.input(p, {'m': 'pad', 'x': double.parse(x.toStringAsFixed(4)), 'y': double.parse(y.toStringAsFixed(4))});
  }

  @override
  void update(double dt) {
    session.update(dt);
    for (final e in session.takeEvents()) {
      switch (e['e']) {
        case 'hit':
          (e['i'] as num) > 2 ? Fx.mid() : Fx.hit();
          hitFlash = 1;
        case 'wall':
          Fx.tap();
        case 'goal':
          lastScorer = e['p'] as int;
          goalAt = time;
          trail.clear();
          Fx.big();
        case 'win':
          endAt = time;
        case 'again':
          showOver = false;
          lastScorer = -1;
          trail.clear();
          setState(() {});
      }
    }
    if (!ready) return;
    hitFlash = math.max(0, hitFlash - dt * 5);

    // المضرب يزحف للإصبع بدل ما يقفز
    for (var p = 0; p < 2; p++) {
      if (!active[p]) continue;
      final f = math.exp(-dt * 10);
      grabX[p] *= f;
      grabY[p] *= f;
      targetX[p] = fingerX[p] + grabX[p];
      targetY[p] = fingerY[p] + grabY[p];
      _send(p);
    }

    if (m.counting || m.over) {
      trail.clear();
    } else {
      trail.add(puckPos());
      if (trail.length > 10) trail.removeAt(0);
    }
    final shouldShow = m.over && time - endAt > 0.5;
    if (shouldShow != showOver) setState(() => showOver = shouldShow);
  }

  void _down(PointerDownEvent e) {
    if (!ready) return;
    final p = _playerOf(e.localPosition);
    if (p < 0) return;
    final l = toLogic(e.localPosition);
    owners[e.pointer] = p;
    // نحفظ الفرق حتى المضرب ما ينط لمكان الإصبع
    final cx = active[p] ? targetX[p] : m.padX[p];
    final cy = active[p] ? targetY[p] : m.padY[p];
    grabX[p] = cx - l.dx;
    grabY[p] = cy - l.dy;
    fingerX[p] = l.dx;
    fingerY[p] = l.dy;
    targetX[p] = cx;
    targetY[p] = cy;
    active[p] = true;
    _send(p, force: true);
  }

  void _move(PointerMoveEvent e) {
    final p = owners[e.pointer];
    if (p == null) return;
    final l = toLogic(e.localPosition);
    fingerX[p] = l.dx;
    fingerY[p] = l.dy;
  }

  void _up(int pointer) {
    final p = owners.remove(pointer);
    if (p != null && !owners.containsValue(p)) {
      active[p] = false;
      session.input(p, {'m': 'rel'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      child: LayoutBuilder(builder: (context, box) {
        _layout(box.biggest);
        if (!ready) return const NetWaiting();
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: (e) => _up(e.pointer),
                onPointerCancel: (e) => _up(e.pointer),
                child: CustomPaint(painter: _HockeyPainter(this)),
              ),
            ),
            if (m.counting)
              Positioned.fill(
                child: Countdown(
                  key: ValueKey('${m.startAt}'),
                  paused: paused && !online,
                  dual: !online,
                  onDone: () {},
                ),
              ),
            if (online) NetBanner(session: session, players: 2),
            if (showOver)
              Positioned.fill(
                child: ResultOverlay(
                  winner: m.winner,
                  scores: m.goals,
                  dual: !online,
                  menuLabel: online ? 'الغرفة' : null,
                  onMenu: roomMenu(context, session),
                  session: session,
                  againLabel: againLabelOf(session),
                  footer: tourFooter(session),
                  names: namesOf(session),
                  onAgain: restart,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _HockeyPainter extends CustomPainter {
  _HockeyPainter(this.s) : super(repaint: s.frame);
  final _HockeyState s;

  @override
  void paint(Canvas canvas, Size size) {
    if (s.tw <= 1 || !s.ready) return;
    final t = s.table;
    final w = s.tw;
    final c = t.center;
    final b = s.bottomP, tp = 1 - b;
    final p0 = C.players[b], p1 = C.players[tp];
    final dual = !s.online;
    final goals = s.m.goals;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF05070D));
    final tr = RRect.fromRectAndRadius(t, Radius.circular(w * 0.08));
    canvas.drawRRect(
      tr,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1B2448), Color(0xFF0D1229)],
          radius: 0.9,
        ).createShader(t),
    );
    // نصف كل لاعب بلونه
    canvas.save();
    canvas.clipRRect(tr);
    canvas.drawRect(Rect.fromLTRB(t.left, c.dy, t.right, t.bottom), Paint()..color = alpha(p0, 0.06));
    canvas.drawRect(Rect.fromLTRB(t.left, t.top, t.right, c.dy), Paint()..color = alpha(p1, 0.06));

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = alpha(Colors.white, 0.16);
    canvas.drawLine(Offset(t.left, c.dy), Offset(t.right, c.dy), line);
    canvas.drawCircle(c, w * 0.17, line);
    canvas.drawCircle(c, 6, Paint()..color = alpha(Colors.white, 0.25));
    // منطقة المرمى
    canvas.drawArc(Rect.fromCircle(center: Offset(c.dx, t.top), radius: s.gw * 1.25), 0, math.pi, false, line..color = alpha(p1, 0.35));
    canvas.drawArc(Rect.fromCircle(center: Offset(c.dx, t.bottom), radius: s.gw * 1.25), math.pi, math.pi, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = alpha(p0, 0.35));

    // النتيجة
    paintText(canvas, '${goals[b]}', Offset(t.right - w * 0.1, c.dy + w * 0.11), size: w * 0.13, color: alpha(p0, 0.85));
    paintText(canvas, '${goals[tp]}', Offset(t.right - w * 0.1, c.dy - w * 0.11), size: w * 0.13, color: alpha(p1, 0.85), flip: dual);
    canvas.restore();

    // الحافة مع فتحات المرمى
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = alpha(Colors.white, 0.35);
    canvas.drawRRect(tr, edge);
    void goal(double y, Color col) {
      final a = Offset(c.dx - s.gw, y), bb = Offset(c.dx + s.gw, y);
      canvas.drawLine(a, bb, Paint()..color = const Color(0xFF05070D)..strokeWidth = 9);
      canvas.drawLine(a, bb, Paint()..color = alpha(col, 0.35)..strokeWidth = 11..strokeCap = StrokeCap.round);
      canvas.drawLine(a, bb, Paint()..color = alpha(col, 0.8)..strokeWidth = 7..strokeCap = StrokeCap.round);
      canvas.drawLine(a, bb, Paint()..color = col..strokeWidth = 4..strokeCap = StrokeCap.round);
    }

    goal(t.top, p1);
    goal(t.bottom, p0);

    // أثر القرص
    for (var i = 0; i < s.trail.length; i++) {
      final k = (i + 1) / s.trail.length;
      canvas.drawCircle(s.trail[i], s.rk * (0.4 + 0.5 * k), Paint()..color = alpha(Colors.white, 0.08 * k));
    }

    // القرص
    final puck = s.puckPos();
    softGlow(canvas, puck, s.rk, alpha(Colors.white, (0.18 + 0.3 * s.hitFlash) * 1.6), s.rk * 0.5);
    canvas.drawCircle(puck, s.rk, Paint()..color = const Color(0xFF151A2E));
    canvas.drawCircle(puck, s.rk, Paint()..style = PaintingStyle.stroke..strokeWidth = s.rk * 0.18..color = Colors.white);
    canvas.drawCircle(puck, s.rk * 0.35, Paint()..color = alpha(Colors.white, 0.25));

    // المضارب
    for (var p = 0; p < 2; p++) {
      final pc = s.padPos(p);
      final col = C.players[p];
      canvas.drawCircle(pc.translate(0, s.rp * 0.12), s.rp * 1.08, Paint()..color = alpha(Colors.black, 0.3));
      paintDisc(canvas, pc, s.rp, col, glow: s.active[p] ? 0.8 : 0.3);
      paintDisc(canvas, pc, s.rp * 0.45, lighten(col, 0.15));
    }

    // هدف!
    final age = s.time - s.goalAt;
    if (age < 1.1 && s.lastScorer >= 0) {
      final k = clamp01(age / 1.1);
      final sc = 0.6 + 0.5 * easeOutBack(clamp01(k * 3));
      final col = C.players[s.lastScorer];
      final op = k > 0.75 ? (1 - k) / 0.25 : 1.0;
      canvas.save();
      canvas.translate(c.dx, c.dy + w * 0.3);
      canvas.scale(sc);
      paintText(canvas, 'هدف!', Offset.zero, size: w * 0.16, color: alpha(col, op), shadows: [Shadow(color: alpha(col, 0.6 * op), blurRadius: 20)]);
      canvas.restore();
      if (dual) {
        canvas.save();
        canvas.translate(c.dx, c.dy - w * 0.3);
        canvas.scale(sc);
        paintText(canvas, 'هدف!', Offset.zero, size: w * 0.16, color: alpha(col, op), flip: true);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
