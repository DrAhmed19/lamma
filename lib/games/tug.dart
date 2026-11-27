import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../logic/tug_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/theme.dart';

/// شد الحبل: لاعبين، كل واحد يضغط بنصّه.
class TugGame extends StatefulWidget {
  const TugGame({super.key, this.room, this.level = 0, this.bots});
  final RoomConn? room;

  /// على نفس الجهاز: المستوى ومقاعد الكمبيوتر (من شاشة البداية)
  final int level;
  final List<bool>? bots;

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
  late final Session<TugModel> session = widget.room != null
      ? OnlineSession<TugModel>(widget.room!)
      : LocalSession(TugModel(players: 2, crazy: false, seed: DateTime.now().microsecondsSinceEpoch, level: widget.level),
          bots: widget.bots, level: widget.level);

  bool isBot(int p) {
    final s = session;
    if (s is LocalSession<TugModel>) return s.isBot(p);
    return false;
  }

  double foulAt = -10;

  TugModel get m => session.model;
  @override
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;
  final _rnd = math.Random();

  double shown = 0;
  final ripples = <_Ripple>[];
  Size size = Size.zero;
  double pulse = 0;
  int round = 0;
  bool showOver = false;
  double endAt = 0;

  // الرسام يقرا هذني
  GamePhase get phase => !ready || m.counting ? GamePhase.countdown : (m.over ? GamePhase.over : GamePhase.play);
  List<int> get taps => m.taps;
  List<int> get wins => m.wins;

  /// أونلاين: إذا آني اللاعب الثاني نقلب الشاشة حتى أكون تحت
  bool get flipped => session.online && session.me == 1;

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
        case 'tap':
          final p = e['p'] as int;
          pulse = 1;
          // مكان الضغطة: بنص اللاعب (أونلاين ما نعرف المكان بالضبط للخصم)
          final h = size.height, w = size.width;
          final bottomHalf = (p == 0) != flipped;
          final y = bottomHalf ? h * (0.55 + 0.4 * _rnd.nextDouble()) : h * (0.05 + 0.4 * _rnd.nextDouble());
          ripples.add(_Ripple(Offset(w * (0.1 + 0.8 * _rnd.nextDouble()), y), C.players[p], time));
          if (!session.online || p == session.me) Fx.tap();
        case 'stop':
          Fx.mid();
        case 'foul':
          if (!session.online || e['p'] == session.me) {
            foulAt = time;
            Fx.hit();
          }
        case 'win':
          endAt = time;
          Fx.big();
          Sfx.play('win');
        case 'again':
          round++;
          showOver = false;
          setState(() {});
      }
    }
    if (!ready) return;
    final target = flipped ? -m.pos : m.pos;
    shown += (target - shown) * (1 - math.exp(-dt * 16));
    ripples.removeWhere((r) => time - r.t0 > 0.6);
    pulse = math.max(0, pulse - dt * 4);
    final shouldShow = m.over && time - endAt > 0.5;
    if (shouldShow != showOver || (m.counting && round == 0)) setState(() => showOver = shouldShow);
  }

  void _down(PointerDownEvent e) {
    if (!ready || m.over || m.counting || paused) return;
    // على نفس الجهاز: النص اللي ضغطت بيه. أونلاين: كل الشاشة إلك.
    final p = session.online ? session.me : (e.localPosition.dy > size.height / 2 ? 0 : 1);
    if (p < 0 || isBot(p)) return;
    session.input(p, {'m': 'tap'});
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      child: LayoutBuilder(builder: (context, box) {
        size = box.biggest;
        if (!ready) return const NetWaiting();
        final online = session.online;
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                child: CustomPaint(painter: _TugPainter(this)),
              ),
            ),
            // «توقف!»: لا تضغط (المتوسط والصعب)
            if (m.level > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<int>(
                    valueListenable: frame,
                    builder: (context, _, __) {
                      final hit = time - foulAt < 0.4;
                      if (!m.stopping && !hit) return const SizedBox();
                      return Container(
                        color: alpha(const Color(0xFFE5303B), m.stopping ? 0.35 : 0.2),
                        alignment: Alignment.center,
                        child: m.stopping
                            ? Text('توقف!', style: display(84, color: Colors.white, shadows: const [Shadow(color: Color(0x66000000), offset: Offset(0, 4), blurRadius: 8)]))
                            : const SizedBox(),
                      );
                    },
                  ),
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
                  scores: m.wins,
                  dual: !online,
                  menuLabel: online ? 'الغرفة' : null,
                  onMenu: roomMenu(context, session),
                  session: session,
                  againLabel: againLabelOf(session),
                  footer: tourFooter(session),
                  names: namesOf(session),
                  subtitle: m.winner >= 0 ? '${m.taps[m.winner]} ضغطة' : null,
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
    // b = اللي تحت، t = اللي فوگ (أونلاين اللاعب الثاني يشوف نفسه تحت)
    final b = s.flipped ? 1 : 0, t = 1 - b;
    final p0 = C.players[b], p1 = C.players[t];

    // منطقة اللاعب الثاني (فوق)
    final top = Rect.fromLTRB(0, 0, w, math.max(split, 1));
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [darken(p1, 0.35), lighten(p1, 0.08)],
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
          colors: [darken(p0, 0.35), lighten(p0, 0.08)],
        ).createShader(bottom),
    );

    // خطوط الفوز: كل لاعب يفوز لما يسحب العقدة لخطّه
    final y1 = h / 2 - reach, y0 = h / 2 + reach;
    dashedLine(canvas, Offset(0, y1), Offset(w, y1), Paint()..color = alpha(p1, 0.8)..strokeWidth = 3);
    dashedLine(canvas, Offset(0, y0), Offset(w, y0), Paint()..color = alpha(p0, 0.8)..strokeWidth = 3);
    dashedLine(canvas, Offset(0, h / 2), Offset(w, h / 2), Paint()..color = alpha(Colors.white, 0.15)..strokeWidth = 2);

    // عدد الضغطات
    paintText(canvas, '${s.taps[b]}', Offset(w / 2, h * 0.76), size: 110, color: alpha(Colors.white, 0.1));
    paintText(canvas, '${s.taps[t]}', Offset(w / 2, h * 0.24), size: 110, color: alpha(Colors.white, 0.1), flip: !s.session.online);
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
        ..color = alpha(Colors.black, 0.22)
        ..strokeWidth = ropeW + 8,
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
    softGlow(canvas, k, kr, alpha(Colors.white, 0.28), kr * 0.6);
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
    paintText(canvas, '${s.wins[b]}', Offset(w - 34, h / 2 + 34), size: 34, color: p0);
    paintText(canvas, '${s.wins[t]}', Offset(w - 34, h / 2 - 34), size: 34, color: p1, flip: !s.session.online);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
