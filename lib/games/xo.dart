import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../logic/xo_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/theme.dart';

/// إكس أو: لاعبين بالدور. القواعد بـ XoModel (نفسها بالسيرفر).
/// room = أونلاين (كل واحد بتلفونه، والسيرفر يحسم).
class XoGame extends StatefulWidget {
  const XoGame({super.key, this.room, this.level = 0, this.bots});
  final RoomConn? room;

  /// على نفس الجهاز: المستوى ومقاعد الكمبيوتر (من شاشة البداية)
  final int level;
  final List<bool>? bots;

  @override
  State<XoGame> createState() => _XoState();
}

class _XoState extends LoopState<XoGame> {
  late final Session<XoModel> session = widget.room != null
      ? OnlineSession<XoModel>(widget.room!)
      : LocalSession(XoModel(players: 2, crazy: false, seed: DateTime.now().microsecondsSinceEpoch, level: widget.level),
          bots: widget.bots, level: widget.level);

  XoModel get m => session.model;
  @override
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;

  /// مؤثرات الرسم (تنحسب بالتطبيق من الأحداث)
  List<double> placedAt = List.filled(81, -10);
  List<double> zoneAt = List.filled(9, -10);

  /// القطع اللي اختفت (المتوسط): مكانها ← (وقتها، صاحبها)
  final Map<int, (double, int)> faded = {};
  double endAt = 0;
  int thinking = -1;

  bool isBot(int p) {
    final s = session;
    if (s is LocalSession<XoModel>) return s.isBot(p);
    if (s is OnlineSession<XoModel>) return s.room.isBot(p);
    return false;
  }
  bool showOver = false;
  Rect boardRect = Rect.zero;

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  void restart() {
    // على نفس الجهاز "من جديد" تبدي جولة جديدة. أونلاين بس بعد ما تخلص.
    if (session.online && !m.over) return;
    session.again();
  }

  @override
  void update(double dt) {
    session.update(dt);
    for (final e in session.takeEvents()) {
      switch (e['e']) {
        case 'put':
          placedAt[e['i'] as int] = time;
          faded.remove(e['i']);
          Fx.hit();
          Sfx.play('pop', volume: 0.6);
        case 'fade':
          faded[e['i'] as int] = (time, e['p'] as int);
          Sfx.play('whoosh', volume: 0.4);
        case 'zone':
          zoneAt[e['z'] as int] = time;
          Fx.mid();
          Sfx.play('gold', volume: 0.5);
        case 'win':
          endAt = time;
          Fx.big();
          Sfx.play('win');
        case 'draw':
          endAt = time;
          Fx.mid();
        case 'again':
          placedAt = List.filled(81, -10);
          zoneAt = List.filled(9, -10);
          faded.clear();
          showOver = false;
          setState(() {});
      }
    }
    if (!ready) return;
    final s = session;
    final t = s is LocalSession<XoModel>
        ? s.thinking
        : (!m.over && isBot(m.turn) ? m.turn : -1);
    if (t != thinking) setState(() => thinking = t);
    final shouldShow = m.over && time - endAt > 1.1;
    if (shouldShow != showOver) setState(() => showOver = shouldShow);
  }

  void _down(PointerDownEvent e) {
    if (!ready || m.over || paused) return;
    final p = e.localPosition;
    if (!boardRect.contains(p)) return;
    final n = m.ultimate ? 9 : 3;
    final cs = boardRect.width / n;
    final col = ((p.dx - boardRect.left) / cs).floor().clamp(0, n - 1);
    final row = ((p.dy - boardRect.top) / cs).floor().clamp(0, n - 1);
    final i = m.ultimate ? ((row ~/ 3) * 3 + col ~/ 3) * 9 + (row % 3) * 3 + col % 3 : row * 3 + col;
    if (!m.legal(i)) return;
    // أونلاين: بس بدوري. على نفس الجهاز: اللي دوره (مو دور الكمبيوتر).
    if (session.online && m.turn != session.me) return;
    if (isBot(m.turn)) return;
    session.input(m.turn, {'m': 'put', 'i': i});
  }

  /// منو تحت ومنو فوگ: أونلاين آني دائماً تحت
  int get bottom => session.online ? math.max(0, session.me) : 0;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest;
        final big = ready && m.ultimate;
        final side = math.min(big ? s.width - 44 : s.width * 0.88, s.height * (big ? 0.6 : 0.52));
        boardRect = Rect.fromCenter(center: s.center(Offset.zero), width: side, height: side);
        if (!ready) return const NetWaiting();
        final top = 1 - bottom;
        final online = session.online;
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                child: CustomPaint(painter: _XoPainter(this)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: s.height * 0.07,
              child: Center(child: _badge(bottom)),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: s.height * 0.07,
              // على نفس الجهاز الخصم مگابلك فننگلب، أونلاين كل واحد بتلفونه
              child: Center(child: online || isBot(top) || isBot(bottom) ? _badge(top) : RotatedBox(quarterTurns: 2, child: _badge(top))),
            ),
            if (online) NetBanner(session: session, players: 2),
            if (showOver)
              Positioned.fill(
                child: ResultOverlay(
                  winner: m.winner,
                  scores: m.wins,
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

  Widget _badge(int p) {
    final active = !m.over && m.turn == p;
    String? label;
    if (session.online) {
      label = p == session.me ? (active ? 'دورك' : 'أنت') : session.nameOf(p);
    }
    if (isBot(p)) label = thinking == p ? 'يفكّر...' : (session.online ? session.nameOf(p) : 'الكمبيوتر');
    return TurnBadge(player: p, active: active, score: m.wins[p], label: label);
  }
}

class _XoPainter extends CustomPainter {
  _XoPainter(this.s) : super(repaint: s.frame);
  final _XoState s;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    paintWorld(canvas, rect, kWorld['xo']!);
    if (!s.ready) return;
    final m = s.m;

    final b = s.boardRect;
    final panel = RRect.fromRectAndRadius(b.inflate(14), const Radius.circular(30));
    canvas.drawRRect(panel.shift(const Offset(0, 7)), Paint()..color = darken(kWorld['xo']!, 0.3));
    canvas.drawRRect(panel, Paint()..color = Colors.white);
    if (m.ultimate) {
      _ultimate(canvas, m, b);
    } else {
      _grid(canvas, b, 1, math.max(5.0, b.width / 3 * 0.05), const Color(0xFFD6E0EE));
      final cs = b.width / 3;
      Offset center(int i) => Offset(b.left + cs * (i % 3 + 0.5), b.top + cs * (i ~/ 3 + 0.5));
      final fade = m.fading;
      for (var i = 0; i < 9; i++) {
        final v = m.board[i];
        if (v < 0) continue;
        final dim = m.over && m.winLine != null && !m.winLine!.contains(i);
        var a = dim ? 0.35 : 1.0;
        // المتوسط: القطعة اللي راح تختفي تنبض خفيف
        if (i == fade) a = 0.35 + 0.25 * (0.5 + 0.5 * math.sin(s.time * 6));
        _mark(canvas, center(i), cs * 0.27, v, clamp01((s.time - s.placedAt[i]) / 0.28), alpha(C.players[v], a), cs);
      }
      // اللي اختفت: تصغر وتروح
      s.faded.forEach((i, f) {
        final t = clamp01((s.time - f.$1) / 0.35);
        if (t >= 1 || m.board[i] >= 0) return;
        _mark(canvas, center(i), cs * 0.27 * (1 - t), f.$2, 1, alpha(C.players[f.$2], 0.4 * (1 - t)), cs);
      });
      final wl = m.winLine;
      if (wl != null) _winLine(canvas, center(wl[0]), center(wl[2]), cs);
    }
  }

  void _grid(Canvas canvas, Rect b, double inset, double w, Color c) {
    final cs = b.width / 3;
    final grid = Paint()
      ..color = c
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    final pad = cs * 0.08 * inset;
    for (var k = 1; k < 3; k++) {
      canvas.drawLine(Offset(b.left + cs * k, b.top + pad), Offset(b.left + cs * k, b.bottom - pad), grid);
      canvas.drawLine(Offset(b.left + pad, b.top + cs * k), Offset(b.right - pad, b.top + cs * k), grid);
    }
  }

  void _ultimate(Canvas canvas, XoModel m, Rect b) {
    final zs = b.width / 3;
    final turnCol = C.players[m.turn];
    for (var z = 0; z < 9; z++) {
      final zr = Rect.fromLTWH(b.left + zs * (z % 3), b.top + zs * (z ~/ 3), zs, zs).deflate(zs * 0.06);
      final open = !m.over && m.big[z] < 0 && (m.zone < 0 || m.zone == z);
      // اللوحات اللي تنلعب هسة تضوي بلون اللي دوره
      if (open) {
        canvas.drawRRect(RRect.fromRectAndRadius(zr.inflate(zs * 0.03), Radius.circular(zs * 0.1)),
            Paint()..color = alpha(turnCol, 0.10 + 0.05 * math.sin(s.time * 4)));
      }
      final inner = zr.deflate(zs * 0.04);
      _grid(canvas, inner, 0.6, math.max(2.0, zs * 0.025), const Color(0xFFD6E0EE));
      final cs = inner.width / 3;
      final won = m.big[z];
      for (var c = 0; c < 9; c++) {
        final v = m.board[z * 9 + c];
        if (v < 0) continue;
        final ctr = Offset(inner.left + cs * (c % 3 + 0.5), inner.top + cs * (c ~/ 3 + 0.5));
        _mark(canvas, ctr, cs * 0.28, v, clamp01((s.time - s.placedAt[z * 9 + c]) / 0.28), alpha(C.players[v], won >= 0 ? 0.25 : 1), cs);
      }
      if (won == 0 || won == 1) {
        final t = clamp01((s.time - s.zoneAt[z]) / 0.4);
        final dim = m.over && m.winLine != null && !m.winLine!.contains(z);
        _mark(canvas, zr.center, zs * 0.3, won, s.zoneAt[z] < 0 ? 1 : t, alpha(C.players[won], dim ? 0.4 : 1), zs * 0.8);
      }
    }
    // خطوط اللوحات الكبيرة
    final bigLine = Paint()
      ..color = L.ink.withValues(alpha: 0.55)
      ..strokeWidth = math.max(4.0, zs * 0.04)
      ..strokeCap = StrokeCap.round;
    for (var k = 1; k < 3; k++) {
      canvas.drawLine(Offset(b.left + zs * k, b.top), Offset(b.left + zs * k, b.bottom), bigLine);
      canvas.drawLine(Offset(b.left, b.top + zs * k), Offset(b.right, b.top + zs * k), bigLine);
    }
    final wl = m.winLine;
    if (wl != null) {
      Offset center(int z) => Offset(b.left + zs * (z % 3 + 0.5), b.top + zs * (z ~/ 3 + 0.5));
      _winLine(canvas, center(wl[0]), center(wl[2]), zs);
    }
  }

  void _mark(Canvas canvas, Offset c, double r, int v, double t, Color color, double cs) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = cs * 0.12
      ..strokeCap = StrokeCap.round;
    if (v == 0) {
      final t1 = clamp01(t * 2), t2 = clamp01(t * 2 - 1);
      final a1 = c + Offset(-r, -r), b1 = c + Offset(r, r);
      final a2 = c + Offset(r, -r), b2 = c + Offset(-r, r);
      if (t1 > 0) canvas.drawLine(a1, Offset.lerp(a1, b1, t1)!, p);
      if (t2 > 0) canvas.drawLine(a2, Offset.lerp(a2, b2, t2)!, p);
    } else {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 2 * easeOutCubic(t), false, p);
    }
  }

  void _winLine(Canvas canvas, Offset a, Offset z, double cs) {
    final t = clamp01((s.time - s.endAt - 0.15) / 0.35);
    final dir = (z - a) / (z - a).distance;
    final a0 = a - dir * cs * 0.38, z0 = z + dir * cs * 0.38;
    final e = Offset.lerp(a0, z0, easeOutCubic(t))!;
    canvas.drawLine(a0, e, Paint()..color = alpha(L.ink, 0.25)..strokeWidth = cs * 0.14..strokeCap = StrokeCap.round);
    canvas.drawLine(a0, e, Paint()..color = L.ink..strokeWidth = cs * 0.07..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
