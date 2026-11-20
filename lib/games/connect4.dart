import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../logic/connect4_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/theme.dart';

/// أربعة بالصف: لاعبين بالدور. القواعد بـ Connect4Model (نفسها بالسيرفر).
class Connect4Game extends StatefulWidget {
  const Connect4Game({super.key, this.room});
  final RoomConn? room;

  @override
  State<Connect4Game> createState() => _C4State();
}

/// قطعة دا تطيح (رسم بس، القاعدة حسمت مكانها)
class _Fall {
  _Fall(this.col, this.row, this.player, this.y);
  final int col, row, player;
  double y; // بالخلايا من فوق اللوحة
  double vy = 0;
  int bounces = 0;
}

class _C4State extends LoopState<Connect4Game> {
  static const cols = Connect4Model.cols, rows = Connect4Model.rows;
  static const pc = [0, 3]; // ألوان: أحمر وأصفر

  late final Session<Connect4Model> session = widget.room != null
      ? OnlineSession<Connect4Model>(widget.room!)
      : LocalSession(Connect4Model(players: 2, crazy: false, seed: DateTime.now().microsecondsSinceEpoch));

  Connect4Model get m => session.model;
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;

  final List<_Fall> falls = [];
  double endAt = -10;
  bool showOver = false;
  bool celebrated = false;
  Rect boardRect = Rect.zero;
  ({int col, int row})? last;

  double get cell => boardRect.width / cols;

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  void restart() {
    if (session.online && !m.over) return;
    session.again();
  }

  @override
  void update(double dt) {
    session.update(dt);
    for (final e in session.takeEvents()) {
      switch (e['e']) {
        case 'drop':
          falls.add(_Fall(e['c'] as int, e['r'] as int, e['p'] as int, -1.2));
          Fx.tap();
        case 'again':
          falls.clear();
          last = null;
          showOver = false;
          celebrated = false;
          endAt = -10;
          setState(() {});
      }
    }
    for (final f in falls) {
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
          f.bounces = 99;
          last = (col: f.col, row: f.row);
          Fx.hit();
          Sfx.play('land', volume: 0.6);
        }
      }
    }
    falls.removeWhere((f) => f.bounces == 99);
    if (!ready) return;
    // الاحتفال لمّن آخر قطعة توصل مكانها
    if (m.over && falls.isEmpty && !celebrated) {
      celebrated = true;
      endAt = time;
      if (m.winner >= 0) {
        Fx.big();
        Sfx.play('win');
      }
    }
    final shouldShow = m.over && celebrated && time - endAt > 1.4;
    if (shouldShow != showOver) setState(() => showOver = shouldShow);
  }

  int _colAt(Offset p) {
    if (p.dx < boardRect.left || p.dx > boardRect.right) return -1;
    return ((p.dx - boardRect.left) / cell).floor().clamp(0, cols - 1);
  }

  void _down(PointerDownEvent e) {
    if (!ready || m.over || paused || falls.isNotEmpty) return;
    final c = _colAt(e.localPosition);
    if (c < 0 || m.freeRow(c) < 0) return;
    if (session.online && m.turn != session.me) return;
    session.input(m.turn, {'m': 'drop', 'c': c});
  }

  /// أونلاين آني دائماً تحت
  int get bottom => session.online ? math.max(0, session.me) : 0;

  /// القطعة اللي دا تطيح ما تنرسم بمكانها لحد ما توصل
  bool hidden(int r, int c) => falls.any((f) => f.row == r && f.col == c);

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest;
        final cw = math.min(s.width * 0.94 / cols, s.height * 0.56 / rows);
        boardRect = Rect.fromCenter(center: s.center(Offset.zero), width: cw * cols, height: cw * rows);
        if (!ready) return const NetWaiting();
        final online = session.online;
        final top = 1 - bottom;
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
              child: Center(child: _badge(bottom)),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: s.height * 0.05,
              child: Center(child: online ? _badge(top) : RotatedBox(quarterTurns: 2, child: _badge(top))),
            ),
            if (online) NetBanner(session: session, players: 2),
            if (showOver)
              Positioned.fill(
                child: ResultOverlay(
                  winner: m.winner,
                  scores: m.wins,
                  seats: pc,
                  dual: !online,
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
      label = p == session.me ? (active ? 'دورك' : 'انت') : session.nameOf(p);
    }
    return TurnBadge(player: pc[p], active: active, score: m.wins[p], label: label);
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
    if (!s.ready) return;
    final m = s.m;
    final b = s.boardRect;
    final cs = s.cell;
    final hr = cs * 0.38;

    Offset cc(int c, double r) => Offset(b.left + cs * (c + 0.5), b.top + cs * (r + 0.5));

    // خلفية الثقوب
    canvas.drawRRect(RRect.fromRectAndRadius(b, Radius.circular(cs * 0.3)), Paint()..color = const Color(0xFF0B1028));

    // القطع
    for (var r = 0; r < _C4State.rows; r++) {
      for (var c = 0; c < _C4State.cols; c++) {
        final v = m.grid[r][c];
        if (v >= 0 && !s.hidden(r, c)) paintDisc(canvas, cc(c, r.toDouble()), hr * 1.02, C.players[_C4State.pc[v]]);
      }
    }
    for (final f in s.falls) {
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
    if (l != null && !m.over) {
      canvas.drawCircle(cc(l.col, l.row.toDouble()), hr * 0.25, Paint()..color = alpha(Colors.white, 0.6));
    }

    // الفوز
    final w = m.winCells;
    if (w != null && s.falls.isEmpty) {
      final k = 0.5 + 0.5 * math.sin((s.time - s.endAt) * 10);
      for (final p in w) {
        final c = cc(p % Connect4Model.cols, (p ~/ Connect4Model.cols).toDouble());
        canvas.drawCircle(c, hr * 1.1, Paint()..style = PaintingStyle.stroke..strokeWidth = cs * 0.08..color = alpha(Colors.white, 0.6 + 0.4 * k));
      }
    }

    // نقاط الدور: جهة اللي دوره (أونلاين: تحت إذا دوري)
    if (!m.over && s.falls.isEmpty) {
      final col = C.players[_C4State.pc[m.turn]];
      final atBottom = m.turn == s.bottom;
      final y = atBottom ? b.bottom + cs * 0.55 : b.top - cs * 0.55;
      final bob = math.sin(s.time * 5) * cs * 0.06;
      for (var c = 0; c < _C4State.cols; c++) {
        canvas.drawCircle(Offset(cc(c, 0).dx, y + bob), cs * 0.07, Paint()..color = alpha(col, 0.55));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
