import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// أربعة بالصف: لاعبين بالدور.
class Connect4Game extends StatefulWidget {
  const Connect4Game({super.key});

  @override
  State<Connect4Game> createState() => _C4State();
}

class _Fall {
  _Fall(this.col, this.row, this.player, this.y);
  final int col, row, player;
  double y; // بالخلايا من فوق اللوحة
  double vy = 0;
  int bounces = 0;
}

class _C4State extends LoopState<Connect4Game> {
  static const cols = 7, rows = 6;
  static const pc = [0, 3]; // ألوان: أحمر وأصفر

  GamePhase phase = GamePhase.play;
  List<List<int>> grid = List.generate(rows, (_) => List.filled(cols, -1));
  int turn = 0;
  int starter = 0;
  _Fall? fall;
  List<math.Point<int>>? winCells;
  int winner = -1;
  bool finished = false;
  double endAt = 0;
  final wins = [0, 0];
  Rect boardRect = Rect.zero;
  int hoverCol = -1;
  ({int col, int row})? last;

  double get cell => boardRect.width / cols;

  @override
  void restart() {
    setState(() {
      starter = 1 - starter;
      turn = starter;
      grid = List.generate(rows, (_) => List.filled(cols, -1));
      fall = null;
      winCells = null;
      winner = -1;
      finished = false;
      last = null;
      phase = GamePhase.play;
    });
  }

  @override
  void update(double dt) {
    final f = fall;
    if (f != null) {
      const g = 70.0; // خلايا/ثانية²
      f.vy += g * dt;
      f.y += f.vy * dt;
      if (f.y >= f.row) {
        f.y = f.row.toDouble();
        if (f.bounces < 1 && f.vy > 6) {
          f.vy = -f.vy * 0.22;
          f.bounces++;
          Fx.tap();
        } else {
          _land(f);
        }
      }
    }
    if (finished && phase == GamePhase.play && time - endAt > 1.4) {
      setState(() => phase = GamePhase.over);
    }
  }

  void _land(_Fall f) {
    fall = null;
    grid[f.row][f.col] = f.player;
    last = (col: f.col, row: f.row);
    Fx.hit();
    final w = _checkWin(f.row, f.col, f.player);
    if (w != null) {
      winCells = w;
      winner = f.player;
      wins[f.player]++;
      finished = true;
      endAt = time;
      Fx.big();
      setState(() {});
      return;
    }
    if (grid[0].every((v) => v >= 0)) {
      winner = -1;
      finished = true;
      endAt = time;
      setState(() {});
      return;
    }
    setState(() => turn = 1 - turn);
  }

  List<math.Point<int>>? _checkWin(int r, int c, int p) {
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (final d in dirs) {
      final cells = <math.Point<int>>[math.Point(c, r)];
      for (final sgn in [1, -1]) {
        var rr = r + d.$1 * sgn, cc = c + d.$2 * sgn;
        while (rr >= 0 && rr < rows && cc >= 0 && cc < cols && grid[rr][cc] == p) {
          cells.add(math.Point(cc, rr));
          rr += d.$1 * sgn;
          cc += d.$2 * sgn;
        }
      }
      if (cells.length >= 4) return cells;
    }
    return null;
  }

  int _colAt(Offset p) {
    if (p.dx < boardRect.left || p.dx > boardRect.right) return -1;
    return ((p.dx - boardRect.left) / cell).floor().clamp(0, cols - 1);
  }

  void _down(PointerDownEvent e) {
    if (finished || paused || fall != null || phase != GamePhase.play) return;
    final c = _colAt(e.localPosition);
    if (c < 0) return;
    var row = -1;
    for (var r = rows - 1; r >= 0; r--) {
      if (grid[r][c] < 0) {
        row = r;
        break;
      }
    }
    if (row < 0) return;
    Fx.tap();
    fall = _Fall(c, row, turn, -1.2);
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest;
        final cw = math.min(s.width * 0.94 / cols, s.height * 0.56 / rows);
        boardRect = Rect.fromCenter(center: s.center(Offset.zero), width: cw * cols, height: cw * rows);
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                child: CustomPaint(painter: _C4Painter(this)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: s.height * 0.05,
              child: Center(child: _badge(0)),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: s.height * 0.05,
              child: Center(child: RotatedBox(quarterTurns: 2, child: _badge(1))),
            ),
            if (phase == GamePhase.over)
              Positioned.fill(
                child: ResultOverlay(
                  winner: winner,
                  scores: wins,
                  seats: pc,
                  dual: true,
                  onAgain: restart,
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _badge(int p) {
    return TurnBadge(
      player: pc[p],
      active: !finished && turn == p,
      score: wins[p],
    );
  }
}

class _C4Painter extends CustomPainter {
  _C4Painter(this.s) : super(repaint: s.frame);
  final _C4State s;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF1A2350), C.bg], radius: 0.9).createShader(rect),
    );
    final b = s.boardRect;
    final cs = s.cell;
    final hr = cs * 0.38;

    Offset cc(int c, double r) => Offset(b.left + cs * (c + 0.5), b.top + cs * (r + 0.5));

    // خلفية الثقوب
    canvas.drawRRect(RRect.fromRectAndRadius(b, Radius.circular(cs * 0.3)), Paint()..color = const Color(0xFF0B1028));

    // القطع
    for (var r = 0; r < _C4State.rows; r++) {
      for (var c = 0; c < _C4State.cols; c++) {
        final v = s.grid[r][c];
        if (v >= 0) paintDisc(canvas, cc(c, r.toDouble()), hr * 1.02, C.players[_C4State.pc[v]]);
      }
    }
    final f = s.fall;
    if (f != null) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, size.width, b.bottom));
      paintDisc(canvas, cc(f.col, f.y), hr * 1.02, C.players[_C4State.pc[f.player]]);
      canvas.restore();
    }

    // اللوحة مع الثقوب
    final panel = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromRectAndRadius(b.inflate(cs * 0.12), Radius.circular(cs * 0.35)));
    for (var r = 0; r < _C4State.rows; r++) {
      for (var c = 0; c < _C4State.cols; c++) {
        panel.addOval(Rect.fromCircle(center: cc(c, r.toDouble()), radius: hr));
      }
    }
    canvas.drawShadow(panel, Colors.black, 10, false);
    canvas.drawPath(
      panel,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3557D6), Color(0xFF223C9E)],
        ).createShader(b.inflate(cs * 0.12)),
    );
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cs * 0.04
      ..color = alpha(Colors.black, 0.25);
    for (var r = 0; r < _C4State.rows; r++) {
      for (var c = 0; c < _C4State.cols; c++) {
        canvas.drawCircle(cc(c, r.toDouble()), hr, rim);
      }
    }

    // آخر حركة
    final l = s.last;
    if (l != null && !s.finished) {
      canvas.drawCircle(cc(l.col, l.row.toDouble()), hr * 0.25, Paint()..color = alpha(Colors.white, 0.6));
    }

    // الفوز
    final w = s.winCells;
    if (w != null) {
      final k = 0.5 + 0.5 * math.sin((s.time - s.endAt) * 10);
      for (final p in w) {
        final c = cc(p.x, p.y.toDouble());
        canvas.drawCircle(c, hr * 1.1, Paint()..style = PaintingStyle.stroke..strokeWidth = cs * 0.08..color = alpha(Colors.white, 0.6 + 0.4 * k));
      }
    }

    // سهم الدور فوق اللوحة
    if (!s.finished && s.fall == null) {
      final col = C.players[_C4State.pc[s.turn]];
      final y = s.turn == 0 ? b.bottom + cs * 0.55 : b.top - cs * 0.55;
      final bob = math.sin(s.time * 5) * cs * 0.06;
      for (var c = 0; c < _C4State.cols; c++) {
        canvas.drawCircle(Offset(cc(c, 0).dx, y + bob), cs * 0.07, Paint()..color = alpha(col, 0.55));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
