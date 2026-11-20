import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// أسرع إصبع: 2-4 لاعبين.
class ReactionGame extends StatefulWidget {
  const ReactionGame({super.key, required this.players});
  final int players;

  @override
  State<ReactionGame> createState() => _ReactionState();
}

enum _R { waiting, decoy, go, roundEnd }

class _Zone {
  const _Zone(this.rect, this.flip);
  final Rect rect;
  final bool flip;
}

class _ReactionState extends LoopState<ReactionGame> {
  static const target = 5;
  final _rnd = math.Random();

  GamePhase phase = GamePhase.countdown;
  _R rs = _R.waiting;
  late List<int> score = List.filled(widget.players, 0);
  late List<bool> fouled = List.filled(widget.players, false);
  double goAt = 0, nextAt = 0, decoyAt = -1, decoyEnd = 0, roundEndAt = 0, foulAt = 0;
  int roundWinner = -1;
  int reactionMs = 0;
  bool wonByFoul = false;
  int winner = -1;
  int round = 0;
  Size size = Size.zero;

  int get n => widget.players;

  List<_Zone> zones(Size s) {
    final w = s.width, h = s.height;
    if (n == 2) {
      return [
        _Zone(Rect.fromLTWH(0, h / 2, w, h / 2), false),
        _Zone(Rect.fromLTWH(0, 0, w, h / 2), true),
      ];
    }
    final q = [
      _Zone(Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2), false),
      _Zone(Rect.fromLTWH(0, 0, w / 2, h / 2), true),
      _Zone(Rect.fromLTWH(0, h / 2, w / 2, h / 2), false),
      _Zone(Rect.fromLTWH(w / 2, 0, w / 2, h / 2), true),
    ];
    return q.sublist(0, n);
  }

  @override
  void restart() {
    setState(() {
      phase = GamePhase.countdown;
      score = List.filled(n, 0);
      fouled = List.filled(n, false);
      rs = _R.waiting;
      goAt = 0;
      nextAt = 0;
      decoyAt = -1;
      decoyEnd = 0;
      roundEndAt = 0;
      foulAt = 0;
      roundWinner = -1;
      reactionMs = 0;
      wonByFoul = false;
      winner = -1;
      round++;
    });
  }

  void _startRound() {
    fouled = List.filled(n, false);
    roundWinner = -1;
    wonByFoul = false;
    rs = _R.waiting;
    final wait = 1.6 + _rnd.nextDouble() * 2.8;
    nextAt = time + wait;
    decoyAt = _rnd.nextDouble() < 0.35 ? time + wait * (0.35 + _rnd.nextDouble() * 0.3) : -1;
  }

  @override
  void update(double dt) {
    if (phase != GamePhase.play) return;
    switch (rs) {
      case _R.waiting:
        if (decoyAt > 0 && time >= decoyAt) {
          rs = _R.decoy;
          decoyEnd = time + 0.5;
          decoyAt = -1;
        } else if (time >= nextAt) {
          rs = _R.go;
          goAt = time;
          Fx.hit();
        }
      case _R.decoy:
        if (time >= decoyEnd) {
          rs = _R.waiting;
          if (time >= nextAt) nextAt = time + 0.6 + _rnd.nextDouble();
        }
      case _R.go:
        break;
      case _R.roundEnd:
        if (time >= roundEndAt) {
          final best = score.reduce(math.max);
          if (best >= target) {
            winner = score.indexOf(best);
            Fx.big();
            setState(() => phase = GamePhase.over);
          } else {
            _startRound();
          }
        }
    }
  }

  void _endRound(int p, {bool byFoul = false}) {
    roundWinner = p;
    wonByFoul = byFoul;
    score[p]++;
    rs = _R.roundEnd;
    roundEndAt = time + 1.5;
  }

  void _down(PointerDownEvent e) {
    if (phase != GamePhase.play || paused) return;
    final zs = zones(size);
    var p = -1;
    for (var i = 0; i < zs.length; i++) {
      if (zs[i].rect.contains(e.localPosition)) p = i;
    }
    if (p < 0 || fouled[p]) return;
    if (rs == _R.go) {
      reactionMs = ((time - goAt) * 1000).round();
      Fx.mid();
      _endRound(p);
    } else if (rs == _R.waiting || rs == _R.decoy) {
      fouled[p] = true;
      foulAt = time;
      Fx.hit();
      final left = [for (var i = 0; i < n; i++) if (!fouled[i]) i];
      if (left.length == 1) _endRound(left.first, byFoul: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      child: LayoutBuilder(builder: (context, box) {
        size = box.biggest;
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                child: CustomPaint(painter: _ReactionPainter(this)),
              ),
            ),
            if (phase == GamePhase.countdown)
              Positioned.fill(
                child: Countdown(
                  key: ValueKey(round),
                  paused: paused,
                  dual: true,
                  onDone: () => setState(() {
                    phase = GamePhase.play;
                    _startRound();
                  }),
                ),
              ),
            if (phase == GamePhase.over)
              Positioned.fill(
                child: ResultOverlay(
                  winner: winner,
                  scores: score,
                  dual: true,
                  onAgain: restart,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _ReactionPainter extends CustomPainter {
  _ReactionPainter(this.s) : super(repaint: s.frame);
  final _ReactionState s;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final zs = s.zones(size);
    final playing = s.phase == GamePhase.play;

    canvas.drawRect(Offset.zero & size, Paint()..color = C.bg);

    for (var i = 0; i < zs.length; i++) {
      final z = zs[i];
      final col = C.players[i];
      final isWin = s.rs == _R.roundEnd && s.roundWinner == i;
      final r = z.rect.deflate(5);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(26));
      var fill = darken(col, 0.68);
      if (isWin) {
        final k = 0.5 + 0.5 * math.sin(s.time * 14);
        fill = Color.lerp(darken(col, 0.2), col, k)!;
      } else if (s.fouled[i]) {
        fill = darken(col, 0.85);
      } else if (s.rs == _R.go) {
        fill = darken(col, 0.45);
      }
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = RadialGradient(
            center: z.flip ? const Alignment(0, -0.4) : const Alignment(0, 0.4),
            radius: 1.1,
            colors: [lighten(fill, 0.08), fill],
          ).createShader(r),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isWin ? 4.0 : 2.0
          ..color = alpha(col, isWin ? 1.0 : 0.5),
      );

      // نص الحالة والنقاط داخل منطقة اللاعب (مقلوب إذا فوق)
      final c = r.center;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      if (z.flip) canvas.rotate(math.pi);
      final half = r.height / 2;
      final small = n4(s.n);

      // النقاط
      const dotsCount = _ReactionState.target;
      final dr = small ? 7.0 : 9.0;
      final gap = dr * 3.0;
      final startX = -gap * (dotsCount - 1) / 2;
      for (var d = 0; d < dotsCount; d++) {
        final p = Offset(startX + d * gap, half - (small ? 26 : 34));
        if (d < s.score[i]) {
          canvas.drawCircle(p, dr * 1.6, Paint()..color = alpha(col, 0.5)..maskFilter = MaskFilter.blur(BlurStyle.normal, dr));
          canvas.drawCircle(p, dr, Paint()..color = lighten(col, 0.2));
        } else {
          canvas.drawCircle(p, dr, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = alpha(col, 0.45));
        }
      }

      String label = '';
      var lc = alpha(Colors.white, 0.8);
      var ls = small ? 30.0 : 40.0;
      if (playing) {
        if (s.fouled[i]) {
          label = 'مبكر!';
          lc = alpha(Colors.white, 0.5);
        } else if (isWin) {
          label = s.wonByFoul ? 'فزت!' : 'فزت!\n${s.reactionMs} ms';
          lc = Colors.white;
          ls = small ? 34.0 : 46.0;
        } else if (s.rs == _R.go) {
          label = 'اضغط!';
          lc = Colors.white;
          ls = small ? 38.0 : 52.0;
        } else if (s.rs == _R.waiting || s.rs == _R.decoy) {
          label = 'انتظر...';
          lc = alpha(Colors.white, 0.55);
        }
      }
      if (label.isNotEmpty) {
        paintText(canvas, label, Offset(0, half * 0.12), size: ls, color: lc, maxWidth: r.width - 20);
      }
      paintText(canvas, C.playerNames[i], Offset(0, -half + (small ? 26 : 34)), size: small ? 16.0 : 20.0, family: kFont, weight: FontWeight.w800, color: alpha(col, 0.9));
      canvas.restore();
    }

    // المنطقة الفارغة لما يكونون 3
    if (s.n == 3) {
      final r = Rect.fromLTWH(w / 2, 0, w / 2, h / 2).deflate(5);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(26)), Paint()..color = alpha(Colors.white, 0.03));
      paintText(canvas, 'لمّة', r.center, size: 40, color: alpha(Colors.white, 0.08), flip: true);
    }

    // الإشارة بالنص
    final c = Offset(w / 2, h / 2);
    final R = math.min(w, h) * 0.13;
    Color sig = const Color(0xFF3A4166);
    switch (s.rs) {
      case _R.go:
        sig = C.go;
      case _R.decoy:
        sig = const Color(0xFFFF8A1F);
      case _R.roundEnd:
        sig = s.roundWinner >= 0 ? C.players[s.roundWinner] : Colors.white;
      case _R.waiting:
        sig = const Color(0xFF3A4166);
    }
    if (!playing) sig = const Color(0xFF3A4166);
    final active = playing && (s.rs == _R.go || s.rs == _R.decoy);
    if (active) {
      final t = s.rs == _R.go ? (s.time - s.goAt) : 0.2;
      for (var k = 0; k < 3; k++) {
        final tt = ((t * 1.6) + k / 3) % 1.0;
        canvas.drawCircle(
          c,
          R * (1 + tt * 1.4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = alpha(sig, 0.6 * (1 - tt)),
        );
      }
      canvas.drawCircle(c, R * 1.5, Paint()..color = alpha(sig, 0.5)..maskFilter = MaskFilter.blur(BlurStyle.normal, R * 0.6));
    } else if (playing && s.rs == _R.waiting) {
      final k = 0.5 + 0.5 * math.sin(s.time * 3);
      canvas.drawCircle(c, R * (1.08 + 0.05 * k), Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = alpha(const Color(0xFFFF4D6A), 0.35 + 0.3 * k));
    }
    canvas.drawCircle(c, R + 6, Paint()..color = C.bg);
    canvas.drawCircle(
      c,
      R,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [lighten(sig, 0.3), sig, darken(sig, 0.3)],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: R)),
    );
    if (playing && s.rs == _R.decoy) {
      paintText(canvas, '!', c, size: R * 1.1, color: Colors.white);
    } else if (playing && s.rs == _R.go) {
      final b = R * 0.55;
      final bolt = Path()
        ..moveTo(c.dx + b * 0.15, c.dy - b)
        ..lineTo(c.dx - b * 0.55, c.dy + b * 0.12)
        ..lineTo(c.dx - b * 0.02, c.dy + b * 0.12)
        ..lineTo(c.dx - b * 0.2, c.dy + b)
        ..lineTo(c.dx + b * 0.6, c.dy - b * 0.2)
        ..lineTo(c.dx + b * 0.06, c.dy - b * 0.2)
        ..close();
      canvas.drawPath(bolt, Paint()..color = Colors.white);
    }
  }

  bool n4(int n) => n > 2;

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
