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
  const XoGame({super.key, this.room});
  final RoomConn? room;

  @override
  State<XoGame> createState() => _XoState();
}

class _XoState extends LoopState<XoGame> {
  late final Session<XoModel> session = widget.room != null
      ? OnlineSession<XoModel>(widget.room!)
      : LocalSession(XoModel(players: 2, crazy: false, seed: DateTime.now().microsecondsSinceEpoch));

  XoModel get m => session.model;
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;

  /// مؤثرات الرسم (تنحسب بالتطبيق من الأحداث)
  List<double> placedAt = List.filled(9, -10);
  double endAt = 0;
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
          Fx.hit();
          Sfx.play('pop', volume: 0.6);
        case 'win':
          endAt = time;
          Fx.big();
          Sfx.play('win');
        case 'draw':
          endAt = time;
          Fx.mid();
        case 'again':
          placedAt = List.filled(9, -10);
          showOver = false;
          setState(() {});
      }
    }
    if (!ready) return;
    final shouldShow = m.over && time - endAt > 1.1;
    if (shouldShow != showOver) setState(() => showOver = shouldShow);
  }

  void _down(PointerDownEvent e) {
    if (!ready || m.over || paused) return;
    final p = e.localPosition;
    if (!boardRect.contains(p)) return;
    final cs = boardRect.width / 3;
    final col = ((p.dx - boardRect.left) / cs).floor().clamp(0, 2);
    final row = ((p.dy - boardRect.top) / cs).floor().clamp(0, 2);
    final i = row * 3 + col;
    if (m.board[i] >= 0) return;
    // أونلاين: بس بدوري. على نفس الجهاز: اللي دوره.
    if (session.online && m.turn != session.me) return;
    session.input(m.turn, {'m': 'put', 'i': i});
  }

  /// منو تحت ومنو فوگ: أونلاين آني دائماً تحت
  int get bottom => session.online ? math.max(0, session.me) : 0;

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest;
        final side = math.min(s.width * 0.88, s.height * 0.52);
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
              child: Center(child: online ? _badge(top) : RotatedBox(quarterTurns: 2, child: _badge(top))),
            ),
            if (online) NetBanner(session: session, players: 2),
            if (showOver)
              Positioned.fill(
                child: ResultOverlay(winner: m.winner, scores: m.wins, dual: !online, onAgain: restart),
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
      label = p == session.me ? (active ? 'دورك' : 'انت') : session.nameOf(p);
    }
    return TurnBadge(player: p, active: active, score: m.wins[p], label: label);
  }
}

class _XoPainter extends CustomPainter {
  _XoPainter(this.s) : super(repaint: s.frame);
  final _XoState s;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1E1748), C.bg],
          radius: 0.9,
        ).createShader(rect),
    );
    if (!s.ready) return;
    final m = s.m;

    final b = s.boardRect;
    final cs = b.width / 3;
    final panel = RRect.fromRectAndRadius(b.inflate(14), const Radius.circular(30));
    canvas.drawRRect(panel, Paint()..color = alpha(Colors.white, 0.04));
    canvas.drawRRect(panel, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = C.line);

    final grid = Paint()
      ..color = alpha(Colors.white, 0.22)
      ..strokeWidth = math.max(5.0, cs * 0.05)
      ..strokeCap = StrokeCap.round;
    for (var k = 1; k < 3; k++) {
      canvas.drawLine(Offset(b.left + cs * k, b.top + 8), Offset(b.left + cs * k, b.bottom - 8), grid);
      canvas.drawLine(Offset(b.left + 8, b.top + cs * k), Offset(b.right - 8, b.top + cs * k), grid);
    }

    Offset center(int i) => Offset(b.left + cs * (i % 3 + 0.5), b.top + cs * (i ~/ 3 + 0.5));

    for (var i = 0; i < 9; i++) {
      final v = m.board[i];
      if (v < 0) continue;
      final t = clamp01((s.time - s.placedAt[i]) / 0.28);
      final c = center(i);
      final r = cs * 0.27;
      final col = C.players[v];
      final dim = m.over && m.winLine != null && !m.winLine!.contains(i);
      final color = dim ? alpha(col, 0.35) : col;
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = cs * 0.12
        ..strokeCap = StrokeCap.round;
      final glow = Paint()
        ..color = alpha(color, 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cs * 0.16
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cs * 0.06);
      if (v == 0) {
        final t1 = clamp01(t * 2), t2 = clamp01(t * 2 - 1);
        final a1 = c + Offset(-r, -r), b1 = c + Offset(r, r);
        final a2 = c + Offset(r, -r), b2 = c + Offset(-r, r);
        for (final pp in [glow, p]) {
          if (t1 > 0) canvas.drawLine(a1, Offset.lerp(a1, b1, t1)!, pp);
          if (t2 > 0) canvas.drawLine(a2, Offset.lerp(a2, b2, t2)!, pp);
        }
      } else {
        final arc = Rect.fromCircle(center: c, radius: r);
        for (final pp in [glow, p]) {
          canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * easeOutCubic(t), false, pp);
        }
      }
    }

    final wl = m.winLine;
    if (wl != null) {
      final t = clamp01((s.time - s.endAt - 0.15) / 0.35);
      final a = center(wl[0]), z = center(wl[2]);
      final dir = (z - a) / (z - a).distance;
      final a0 = a - dir * cs * 0.38, z0 = z + dir * cs * 0.38;
      final e = Offset.lerp(a0, z0, easeOutCubic(t))!;
      canvas.drawLine(a0, e, Paint()..color = alpha(Colors.white, 0.6)..strokeWidth = cs * 0.14..strokeCap = StrokeCap.round..maskFilter = MaskFilter.blur(BlurStyle.normal, cs * 0.08));
      canvas.drawLine(a0, e, Paint()..color = Colors.white..strokeWidth = cs * 0.07..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
