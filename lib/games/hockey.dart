import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// هوكي الهواء: لاعبين، كل واحد بنصّه.
class HockeyGame extends StatefulWidget {
  const HockeyGame({super.key});

  @override
  State<HockeyGame> createState() => _HockeyState();
}

class _HockeyState extends LoopState<HockeyGame> {
  static const target = 7;

  GamePhase phase = GamePhase.countdown;
  Size size = Size.zero;
  Rect table = Rect.zero;
  double rp = 0, rk = 0, gw = 0;

  Offset puck = Offset.zero, puckV = Offset.zero;
  final pads = [Offset.zero, Offset.zero];
  final padV = [Offset.zero, Offset.zero];
  final List<Offset?> padTarget = [null, null];

  /// فرق المضرب عن الإصبع لحظة اللمس؛ يذوب تدريجياً حتى المضرب يزحف للإصبع بدل ما يقفز.
  final grab = [Offset.zero, Offset.zero];
  final owners = <int, int>{};
  final scores = [0, 0];
  final trail = <Offset>[];
  double goalUntil = 0;
  int lastScorer = -1;
  double hitFlash = 0;
  int winner = -1;
  int round = 0;
  bool _ready = false;

  void _layout(Size s) {
    if (s == size && _ready) return;
    if (s.width <= 0 || s.height <= 0) return;
    final old = table;
    final oldW = size.width;
    size = s;
    final m = 6.0;
    table = Rect.fromLTRB(m, m, s.width - m, s.height - m);
    rp = s.width * 0.085;
    rk = s.width * 0.052;
    gw = s.width * 0.19;
    if (!_ready) {
      _ready = true;
      _resetPositions(serveTo: -1);
      return;
    }
    // تغيّر حجم الشاشة: ننقل كل شي بنفس النسبة للطاولة الجديدة
    Offset map(Offset p) => Offset(
          table.left + (p.dx - old.left) / old.width * table.width,
          table.top + (p.dy - old.top) / old.height * table.height,
        );
    final sv = oldW > 0 ? s.width / oldW : 1.0;
    puck = map(puck);
    puckV = puckV * sv;
    puck = Offset(
      puck.dx.clamp(table.left + rk, table.right - rk).toDouble(),
      puck.dy.clamp(table.top + rk, table.bottom - rk).toDouble(),
    );
    for (var p = 0; p < 2; p++) {
      pads[p] = _clampPad(p, map(pads[p]));
      padV[p] = Offset.zero;
      grab[p] = Offset.zero;
      // الإصبع لازم يرفع وينزل من جديد بعد تغيّر الحجم
      padTarget[p] = null;
    }
    owners.clear();
    trail.clear();
  }

  void _resetPositions({required int serveTo}) {
    final c = table.center;
    pads[0] = Offset(c.dx, table.bottom - table.height * 0.18);
    pads[1] = Offset(c.dx, table.top + table.height * 0.18);
    padV[0] = Offset.zero;
    padV[1] = Offset.zero;
    padTarget[0] = null;
    padTarget[1] = null;
    grab[0] = Offset.zero;
    grab[1] = Offset.zero;
    final dy = serveTo == 0 ? table.height * 0.1 : (serveTo == 1 ? -table.height * 0.1 : 0.0);
    puck = c.translate(0, dy);
    puckV = Offset.zero;
    trail.clear();
  }

  @override
  void restart() {
    setState(() {
      scores[0] = 0;
      scores[1] = 0;
      winner = -1;
      lastScorer = -1;
      goalUntil = 0;
      owners.clear();
      _resetPositions(serveTo: -1);
      phase = GamePhase.countdown;
      round++;
    });
  }

  Offset _clampPad(int p, Offset t) {
    final x = t.dx.clamp(table.left + rp, table.right - rp);
    final mid = table.center.dy;
    final y = p == 0 ? t.dy.clamp(mid + rp * 0.6, table.bottom - rp) : t.dy.clamp(table.top + rp, mid - rp * 0.6);
    return Offset(x.toDouble(), y.toDouble());
  }

  @override
  void update(double dt) {
    if (!_ready || dt <= 0) return;
    hitFlash = math.max(0, hitFlash - dt * 5);

    // المضارب تتبع الأصابع
    for (var p = 0; p < 2; p++) {
      final t = padTarget[p];
      if (t == null) {
        padV[p] = padV[p] * math.exp(-dt * 20);
        continue;
      }
      grab[p] = grab[p] * math.exp(-dt * 10);
      if (grab[p].distanceSquared < 0.25) grab[p] = Offset.zero;
      final np = _clampPad(p, t + grab[p]);
      var v = (np - pads[p]) / dt;
      final maxV = size.width * 7;
      if (v.distance > maxV) v = v / v.distance * maxV;
      padV[p] = Offset.lerp(padV[p], v, 0.6)!;
      pads[p] = np;
    }

    if (phase != GamePhase.play) return;
    if (time < goalUntil) return;

    const steps = 4;
    final sdt = dt / steps;
    final maxSpeed = size.width * 3.6;
    for (var i = 0; i < steps; i++) {
      puck += puckV * sdt;
      var x = puck.dx, y = puck.dy;
      var vx = puckV.dx, vy = puckV.dy;
      final inGoal = (x - table.center.dx).abs() < gw - rk * 0.3;

      if (x < table.left + rk) {
        x = table.left + rk;
        vx = vx.abs() * 0.9;
        _wallHit();
      } else if (x > table.right - rk) {
        x = table.right - rk;
        vx = -vx.abs() * 0.9;
        _wallHit();
      }
      if (y < table.top + rk) {
        if (inGoal) {
          if (y < table.top - rk) {
            _goal(0);
            return;
          }
        } else {
          y = table.top + rk;
          vy = vy.abs() * 0.9;
          _wallHit();
        }
      } else if (y > table.bottom - rk) {
        if (inGoal) {
          if (y > table.bottom + rk) {
            _goal(1);
            return;
          }
        } else {
          y = table.bottom - rk;
          vy = -vy.abs() * 0.9;
          _wallHit();
        }
      }
      puck = Offset(x, y);
      puckV = Offset(vx, vy);

      for (var p = 0; p < 2; p++) {
        final d = puck - pads[p];
        final dist = d.distance;
        final minD = rp + rk;
        if (dist < minD && dist > 0.0001) {
          final nrm = d / dist;
          puck = pads[p] + nrm * minD;
          final rel = puckV - padV[p];
          final vn = rel.dx * nrm.dx + rel.dy * nrm.dy;
          if (vn < 0) {
            puckV = puckV - nrm * (1.85 * vn);
            final impact = -vn / size.width;
            if (impact > 0.4) {
              hitFlash = 1;
              if (impact > 2) {
                Fx.mid();
              } else {
                Fx.hit();
              }
            }
          }
        }
      }
      final sp = puckV.distance;
      if (sp > maxSpeed) puckV = puckV / sp * maxSpeed;
      puckV = puckV * math.exp(-0.28 * sdt);
    }

    trail.add(puck);
    if (trail.length > 10) trail.removeAt(0);
  }

  double _lastWall = 0;
  void _wallHit() {
    if (time - _lastWall > 0.08 && puckV.distance > size.width * 0.6) {
      Fx.tap();
      _lastWall = time;
    }
  }

  void _goal(int scorer) {
    scores[scorer]++;
    lastScorer = scorer;
    Fx.big();
    if (scores[scorer] >= target) {
      winner = scorer;
      setState(() => phase = GamePhase.over);
      return;
    }
    goalUntil = time + 1.1;
    final conceder = 1 - scorer;
    final c = table.center;
    puck = c.translate(0, conceder == 0 ? table.height * 0.1 : -table.height * 0.1);
    puckV = Offset.zero;
    trail.clear();
    setState(() {});
  }

  void _down(PointerDownEvent e) {
    final p = e.localPosition.dy > size.height / 2 ? 0 : 1;
    owners[e.pointer] = p;
    // نحفظ الفرق حتى المضرب ما ينط لمكان الإصبع
    grab[p] = pads[p] - e.localPosition;
    padTarget[p] = e.localPosition;
  }

  void _move(PointerMoveEvent e) {
    final p = owners[e.pointer];
    if (p != null) padTarget[p] = e.localPosition;
  }

  void _up(int pointer) {
    final p = owners.remove(pointer);
    if (p != null && !owners.containsValue(p)) padTarget[p] = null;
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      child: LayoutBuilder(builder: (context, box) {
        _layout(box.biggest);
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
            if (phase == GamePhase.countdown)
              Positioned.fill(
                child: Countdown(
                  key: ValueKey(round),
                  paused: paused,
                  dual: true,
                  onDone: () => setState(() => phase = GamePhase.play),
                ),
              ),
            if (phase == GamePhase.over)
              Positioned.fill(
                child: ResultOverlay(winner: winner, scores: scores, dual: true, onAgain: restart),
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
    if (!s._ready) return;
    final t = s.table;
    final w = size.width;
    final c = t.center;
    final p0 = C.players[0], p1 = C.players[1];

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
    paintText(canvas, '${s.scores[0]}', Offset(t.right - w * 0.1, c.dy + w * 0.11), size: w * 0.13, color: alpha(p0, 0.85));
    paintText(canvas, '${s.scores[1]}', Offset(t.right - w * 0.1, c.dy - w * 0.11), size: w * 0.13, color: alpha(p1, 0.85), flip: true);
    canvas.restore();

    // الحافة مع فتحات المرمى
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = alpha(Colors.white, 0.35);
    canvas.drawRRect(tr, edge);
    void goal(double y, Color col) {
      final a = Offset(c.dx - s.gw, y), b = Offset(c.dx + s.gw, y);
      canvas.drawLine(a, b, Paint()..color = const Color(0xFF05070D)..strokeWidth = 9);
      canvas.drawLine(a, b, Paint()..color = alpha(col, 0.8)..strokeWidth = 7..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawLine(a, b, Paint()..color = col..strokeWidth = 4..strokeCap = StrokeCap.round);
    }

    goal(t.top, p1);
    goal(t.bottom, p0);

    // أثر القرص
    for (var i = 0; i < s.trail.length; i++) {
      final k = (i + 1) / s.trail.length;
      canvas.drawCircle(s.trail[i], s.rk * (0.4 + 0.5 * k), Paint()..color = alpha(Colors.white, 0.08 * k));
    }

    // القرص
    canvas.drawCircle(s.puck, s.rk * 1.4, Paint()..color = alpha(Colors.white, 0.18 + 0.3 * s.hitFlash)..maskFilter = MaskFilter.blur(BlurStyle.normal, s.rk * 0.6));
    canvas.drawCircle(s.puck, s.rk, Paint()..color = const Color(0xFF151A2E));
    canvas.drawCircle(s.puck, s.rk, Paint()..style = PaintingStyle.stroke..strokeWidth = s.rk * 0.18..color = Colors.white);
    canvas.drawCircle(s.puck, s.rk * 0.35, Paint()..color = alpha(Colors.white, 0.25));

    // المضارب
    for (var p = 0; p < 2; p++) {
      final pc = s.pads[p];
      final col = C.players[p];
      canvas.drawCircle(pc.translate(0, s.rp * 0.12), s.rp * 1.05, Paint()..color = alpha(Colors.black, 0.45)..maskFilter = MaskFilter.blur(BlurStyle.normal, s.rp * 0.25));
      paintDisc(canvas, pc, s.rp, col, glow: s.padTarget[p] != null ? 0.8 : 0.3);
      paintDisc(canvas, pc, s.rp * 0.45, lighten(col, 0.15));
    }

    // هدف!
    if (s.time < s.goalUntil && s.lastScorer >= 0) {
      final k = clamp01(1 - (s.goalUntil - s.time) / 1.1);
      final sc = 0.6 + 0.5 * easeOutBack(clamp01(k * 3));
      final col = C.players[s.lastScorer];
      final op = k > 0.75 ? (1 - k) / 0.25 : 1.0;
      canvas.save();
      canvas.translate(c.dx, c.dy + w * 0.3);
      canvas.scale(sc);
      paintText(canvas, 'هدف!', Offset.zero, size: w * 0.16, color: alpha(col, op), shadows: [Shadow(color: alpha(col, 0.6 * op), blurRadius: 20)]);
      canvas.restore();
      canvas.save();
      canvas.translate(c.dx, c.dy - w * 0.3);
      canvas.scale(sc);
      paintText(canvas, 'هدف!', Offset.zero, size: w * 0.16, color: alpha(col, op), flip: true);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
