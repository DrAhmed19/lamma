import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../ui/kit.dart';
import '../ui/theme.dart';

/// شد الحبل: لاعبين، كل واحد يضغط بنصّه.
class TugGame extends StatefulWidget {
  const TugGame({super.key});

  @override
  State<TugGame> createState() => _TugState();
}

class _Ripple {
  _Ripple(this.p, this.color, this.t0);
  final Offset p;
  final Color color;
  final double t0;
}

class _TugState extends LoopState<TugGame> {
  static const _step = 0.045;

  GamePhase phase = GamePhase.countdown;
  double target = 0; // -1..1 ، الموجب لصالح اللاعب الأول (تحت) — العقدة تنسحب صوب اللي يضغط
  double shown = 0;
  final taps = [0, 0];
  final wins = [0, 0];
  int winner = -1;
  final ripples = <_Ripple>[];
  Size size = Size.zero;
  double pulse = 0;
  int round = 0;

  @override
  void restart() {
    setState(() {
      phase = GamePhase.countdown;
      target = 0;
      shown = 0;
      taps[0] = 0;
      taps[1] = 0;
      ripples.clear();
      winner = -1;
      round++;
    });
  }

  @override
  void update(double dt) {
    shown += (target - shown) * (1 - math.exp(-dt * 16));
    ripples.removeWhere((r) => time - r.t0 > 0.6);
    pulse = math.max(0, pulse - dt * 4);
  }

  void _down(PointerDownEvent e) {
    if (phase != GamePhase.play || paused) return;
    final p = e.localPosition.dy > size.height / 2 ? 0 : 1;
    taps[p]++;
    target += p == 0 ? _step : -_step;
    pulse = 1;
    ripples.add(_Ripple(e.localPosition, C.players[p], time));
    Fx.tap();
    if (target.abs() >= 1) {
      target = target.sign;
      winner = target > 0 ? 0 : 1;
      wins[winner]++;
      Fx.big();
      setState(() => phase = GamePhase.over);
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
                child: CustomPaint(painter: _TugPainter(this)),
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
                child: ResultOverlay(
                  winner: winner,
                  scores: wins,
                  dual: true,
                  subtitle: '${taps[winner]} ضغطة',
                  onAgain: restart,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _TugPainter extends CustomPainter {
  _TugPainter(this.s) : super(repaint: s.frame);
  final _TugState s;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final reach = h / 2 * 0.86;
    // العقدة تنسحب صوب اللاعب اللي يضغط (الأول تحت، الثاني فوق)
    final by = h / 2 + s.shown * reach;
    // حد المنطقتين يمشي بعكس العقدة: اللي يسحب تكبر ساحته
    final split = h / 2 - s.shown * reach;
    final p0 = C.players[0], p1 = C.players[1];

    // منطقة اللاعب الثاني (فوق)
    final top = Rect.fromLTRB(0, 0, w, math.max(split, 1));
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [darken(p1, 0.72), darken(p1, 0.25)],
        ).createShader(top),
    );
    // منطقة اللاعب الأول (تحت)
    final bottom = Rect.fromLTRB(0, math.min(split, h - 1), w, h);
    canvas.drawRect(
      bottom,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [darken(p0, 0.72), darken(p0, 0.25)],
        ).createShader(bottom),
    );

    // خطوط الفوز: كل لاعب يفوز لما يسحب العقدة لخطّه
    final y1 = h / 2 - reach, y0 = h / 2 + reach;
    dashedLine(canvas, Offset(0, y1), Offset(w, y1), Paint()..color = alpha(p1, 0.8)..strokeWidth = 3);
    dashedLine(canvas, Offset(0, y0), Offset(w, y0), Paint()..color = alpha(p0, 0.8)..strokeWidth = 3);
    dashedLine(canvas, Offset(0, h / 2), Offset(w, h / 2), Paint()..color = alpha(Colors.white, 0.15)..strokeWidth = 2);

    // عدد الضغطات
    paintText(canvas, '${s.taps[0]}', Offset(w / 2, h * 0.76), size: 110, color: alpha(Colors.white, 0.1));
    paintText(canvas, '${s.taps[1]}', Offset(w / 2, h * 0.24), size: 110, color: alpha(Colors.white, 0.1), flip: true);
    if (s.phase == GamePhase.play && s.taps[0] + s.taps[1] < 3) {
      paintText(canvas, 'اضغط بسرعة!', Offset(w / 2, h * 0.88), size: 30, color: alpha(Colors.white, 0.7));
      paintText(canvas, 'اضغط بسرعة!', Offset(w / 2, h * 0.12), size: 30, color: alpha(Colors.white, 0.7), flip: true);
    }

    // توهج الحد الفاصل
    final glowRect = Rect.fromLTRB(0, split - 40, w, split + 40);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [alpha(Colors.white, 0), alpha(Colors.white, 0.12 + 0.15 * s.pulse), alpha(Colors.white, 0)],
        ).createShader(glowRect),
    );

    // الحبل
    final rx = w / 2;
    final ropeW = math.max(14.0, w * 0.04);
    canvas.drawLine(
      Offset(rx, 0),
      Offset(rx, h),
      Paint()
        ..color = alpha(Colors.black, 0.35)
        ..strokeWidth = ropeW + 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(Offset(rx, 0), Offset(rx, h), Paint()..color = const Color(0xFF8A6A3D)..strokeWidth = ropeW + 4);
    canvas.drawLine(Offset(rx, 0), Offset(rx, h), Paint()..color = const Color(0xFFE2BE84)..strokeWidth = ropeW);
    final braid = Paint()
      ..color = const Color(0xFFA9834D)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const gap = 16.0;
    final off = (s.shown * reach) % gap;
    for (var y = -gap + off; y < h + gap; y += gap) {
      canvas.drawLine(Offset(rx - ropeW / 2 + 2, y), Offset(rx + ropeW / 2 - 2, y + gap * 0.6), braid);
    }

    // العقدة (العلامة)
    final k = Offset(rx, by);
    final kr = math.max(20.0, w * 0.055) * (1 + 0.12 * s.pulse);
    canvas.drawCircle(k, kr * 1.6, Paint()..color = alpha(Colors.white, 0.18)..maskFilter = MaskFilter.blur(BlurStyle.normal, kr * 0.6));
    final flag = Rect.fromCenter(center: k, width: kr * 4.2, height: kr * 0.7);
    canvas.drawRRect(RRect.fromRectAndRadius(flag, Radius.circular(kr * 0.35)), Paint()..color = const Color(0xFFFFC93C));
    canvas.drawCircle(k, kr, Paint()..color = Colors.white);
    canvas.drawCircle(k, kr * 0.62, Paint()..color = const Color(0xFFFFC93C));

    // تموجات الضغط
    for (final r in s.ripples) {
      final t = clamp01((s.time - r.t0) / 0.6);
      canvas.drawCircle(
        r.p,
        16 + 70 * easeOutCubic(t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - t) + 1
          ..color = alpha(lighten(r.color, 0.5), 0.7 * (1 - t)),
      );
    }

    // نتيجة الجولات
    paintText(canvas, '${s.wins[0]}', Offset(w - 34, h / 2 + 34), size: 34, color: p0);
    paintText(canvas, '${s.wins[1]}', Offset(w - 34, h / 2 - 34), size: 34, color: p1, flip: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
