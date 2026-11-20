import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// إكس أو: لاعبين بالدور.
class XoGame extends StatefulWidget {
  const XoGame({super.key});

  @override
  State<XoGame> createState() => _XoState();
}

class _XoState extends LoopState<XoGame> {
  static const lines = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  GamePhase phase = GamePhase.play;
  List<int> board = List.filled(9, -1);
  List<double> placedAt = List.filled(9, 0);
  int turn = 0;
  int starter = 0;
  List<int>? winLine;
  int winner = -1;
  bool finished = false;
  double endAt = 0;
  final wins = [0, 0];
  Rect boardRect = Rect.zero;

  @override
  void restart() {
    setState(() {
      starter = 1 - starter;
      turn = starter;
      board = List.filled(9, -1);
      placedAt = List.filled(9, 0);
      winLine = null;
      winner = -1;
      finished = false;
      phase = GamePhase.play;
    });
  }

  @override
  void update(double dt) {
    if (finished && phase == GamePhase.play && time - endAt > 1.1) {
      setState(() => phase = GamePhase.over);
    }
  }

  void _down(PointerDownEvent e) {
    if (finished || paused || phase != GamePhase.play) return;
    final p = e.localPosition;
    if (!boardRect.contains(p)) return;
    final cs = boardRect.width / 3;
    final col = ((p.dx - boardRect.left) / cs).floor().clamp(0, 2);
    final row = ((p.dy - boardRect.top) / cs).floor().clamp(0, 2);
    final i = row * 3 + col;
    if (board[i] >= 0) return;
    setState(() {
      board[i] = turn;
      placedAt[i] = time;
    });
    Fx.hit();
    for (final l in lines) {
      if (board[l[0]] == turn && board[l[1]] == turn && board[l[2]] == turn) {
        winLine = l;
        winner = turn;
        wins[turn]++;
        finished = true;
        endAt = time;
        Fx.big();
        setState(() {});
        return;
      }
    }
    if (!board.contains(-1)) {
      winner = -1;
      finished = true;
      endAt = time;
      Fx.mid();
      setState(() {});
      return;
    }
    setState(() => turn = 1 - turn);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest;
        final side = math.min(s.width * 0.88, s.height * 0.52);
        boardRect = Rect.fromCenter(center: s.center(Offset.zero), width: side, height: side);
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
              child: Center(child: TurnBadge(player: 0, active: !finished && turn == 0, score: wins[0])),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: s.height * 0.07,
              child: Center(
                child: RotatedBox(
                  quarterTurns: 2,
                  child: TurnBadge(player: 1, active: !finished && turn == 1, score: wins[1]),
                ),
              ),
            ),
            if (phase == GamePhase.over)
              Positioned.fill(
                child: ResultOverlay(winner: winner, scores: wins, dual: true, onAgain: restart),
              ),
          ],
        );
      }),
    );
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
      final v = s.board[i];
      if (v < 0) continue;
      final t = clamp01((s.time - s.placedAt[i]) / 0.28);
      final c = center(i);
      final r = cs * 0.27;
      final col = C.players[v];
      final dim = s.finished && s.winLine != null && !s.winLine!.contains(i);
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

    final wl = s.winLine;
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
