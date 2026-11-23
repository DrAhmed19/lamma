import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/draw.dart';
import '../core/fx.dart';
import '../core/profile.dart';
import '../core/loop.dart';
import '../logic/reaction_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/theme.dart';

/// أسرع إصبع: 2-4 لاعبين. القواعد بـ ReactionModel (نفسها بالسيرفر).
class ReactionGame extends StatefulWidget {
  const ReactionGame({super.key, required this.players, this.room});
  final int players;
  final RoomConn? room;

  @override
  State<ReactionGame> createState() => _ReactionState();
}

class _Zone {
  const _Zone(this.rect, this.flip);
  final Rect rect;
  final bool flip;
}

class _ReactionState extends LoopState<ReactionGame> {
  late final Session<ReactionModel> session = widget.room != null
      ? OnlineSession<ReactionModel>(widget.room!)
      : LocalSession(ReactionModel(players: widget.players, crazy: false, seed: DateTime.now().microsecondsSinceEpoch));

  ReactionModel get m => session.model;
  @override
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;
  bool get online => session.online;

  Size size = Size.zero;
  double endAt = 0;
  bool showOver = false;

  int get n => ready ? m.players : widget.players;

  // الرسام يقرا هذني
  GamePhase get phase => !ready || m.counting ? GamePhase.countdown : (showOver ? GamePhase.over : GamePhase.play);
  int get rs => m.rs;
  List<int> get score => m.score;
  List<bool> get fouled => m.fouled;
  int get roundWinner => m.roundWinner;
  int get reactionMs => m.reactionMs;
  bool get wonByFoul => m.wonByFoul;
  double get goAt => m.goAt;
  double get gt => m.time;

  /// أي لاعب بأي مربع. أونلاين: آني دائماً بالمربع الأول (تحت) وكل شي مو مقلوب.
  List<int> get order {
    if (!online || session.me < 0) return [for (var i = 0; i < n; i++) i];
    final me = session.me;
    return [me, for (var i = 0; i < n; i++) if (i != me) i];
  }

  String nameOfPlayer(int p) => online ? session.nameOf(p) : C.playerNames[p];

  List<_Zone> zones(Size s) {
    final w = s.width, h = s.height;
    final fl = !online;
    if (n == 2) {
      return [
        _Zone(Rect.fromLTWH(0, h / 2, w, h / 2), false),
        _Zone(Rect.fromLTWH(0, 0, w, h / 2), fl),
      ];
    }
    final q = [
      _Zone(Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2), false),
      _Zone(Rect.fromLTWH(0, 0, w / 2, h / 2), fl),
      _Zone(Rect.fromLTWH(0, h / 2, w / 2, h / 2), false),
      _Zone(Rect.fromLTWH(w / 2, 0, w / 2, h / 2), fl),
    ];
    return q.sublist(0, n);
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

  @override
  void update(double dt) {
    session.update(dt);
    for (final e in session.takeEvents()) {
      switch (e['e']) {
        case 'go':
          Fx.hit();
        case 'tap':
          Fx.mid();
          // أسرع استجابة (ألقاب الملف الشخصي)
          if (!online || e['p'] == session.me) Profile.I.recordReaction((e['ms'] as num).toInt());
        case 'foul':
          Fx.hit();
        case 'win':
          endAt = time;
          Fx.big();
        case 'again':
          showOver = false;
          setState(() {});
      }
    }
    if (!ready) return;
    final shouldShow = m.over && time - endAt > 0.6;
    if (shouldShow != showOver) setState(() => showOver = shouldShow);
  }

  void _down(PointerDownEvent e) {
    if (!ready || m.counting || m.over || paused) return;
    if (online) {
      if (session.me >= 0) session.input(session.me, {'m': 'tap'});
      return;
    }
    final zs = zones(size);
    var p = -1;
    for (var i = 0; i < zs.length; i++) {
      if (zs[i].rect.contains(e.localPosition)) p = i;
    }
    if (p < 0) return;
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
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                child: CustomPaint(painter: _ReactionPainter(this)),
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
            if (online) NetBanner(session: session, players: n),
            if (showOver)
              Positioned.fill(
                child: ResultOverlay(
                  winner: m.winner,
                  scores: m.score,
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

class _ReactionPainter extends CustomPainter {
  _ReactionPainter(this.s) : super(repaint: s.frame);
  final _ReactionState s;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final zs = s.zones(size);
    final playing = s.phase == GamePhase.play;

    paintWorld(canvas, Offset.zero & size, kWorld['reaction']!);

    final ord = s.order;
    for (var zi = 0; zi < zs.length; zi++) {
      final z = zs[zi];
      final i = ord[zi];
      final col = C.players[i];
      final isWin = s.rs == ReactionModel.roundEnd && s.roundWinner == i;
      final r = z.rect.deflate(5);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(26));
      var fill = darken(col, 0.45);
      if (isWin) {
        final k = 0.5 + 0.5 * math.sin(s.time * 14);
        fill = Color.lerp(darken(col, 0.2), col, k)!;
      } else if (s.fouled[i]) {
        fill = darken(col, 0.7);
      } else if (s.rs == ReactionModel.go) {
        fill = darken(col, 0.12);
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
      const dotsCount = ReactionModel.target;
      final dr = small ? 7.0 : 9.0;
      final gap = dr * 3.0;
      final startX = -gap * (dotsCount - 1) / 2;
      for (var d = 0; d < dotsCount; d++) {
        final p = Offset(startX + d * gap, half - (small ? 26 : 34));
        if (d < s.score[i]) {
          softGlow(canvas, p, dr, alpha(col, 0.8), dr * 0.6);
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
          label = 'مبكّر!';
          lc = alpha(Colors.white, 0.5);
        } else if (isWin) {
          label = s.wonByFoul ? 'فزت!' : 'فزت!\n${s.reactionMs} ms';
          lc = Colors.white;
          ls = small ? 34.0 : 46.0;
        } else if (s.rs == ReactionModel.go) {
          label = 'اضغط!';
          lc = Colors.white;
          ls = small ? 38.0 : 52.0;
        } else if (s.rs == ReactionModel.waiting || s.rs == ReactionModel.decoy) {
          label = 'انتظر...';
          lc = alpha(Colors.white, 0.55);
        }
      }
      if (label.isNotEmpty) {
        paintText(canvas, label, Offset(0, half * 0.12), size: ls, color: lc, maxWidth: r.width - 20);
      }
      paintText(canvas, s.nameOfPlayer(i), Offset(0, -half + (small ? 26 : 34)), size: small ? 16.0 : 20.0, family: kFont, weight: FontWeight.w800, color: alpha(col, 0.9));
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
      case ReactionModel.go:
        sig = C.go;
      case ReactionModel.decoy:
        sig = const Color(0xFFFF8A1F);
      case ReactionModel.roundEnd:
        sig = s.roundWinner >= 0 ? C.players[s.roundWinner] : Colors.white;
      case ReactionModel.waiting:
        sig = const Color(0xFF3A4166);
    }
    if (!playing) sig = const Color(0xFF3A4166);
    final active = playing && (s.rs == ReactionModel.go || s.rs == ReactionModel.decoy);
    if (active) {
      final t = s.rs == ReactionModel.go ? (s.gt - s.goAt) : 0.2;
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
      softGlow(canvas, c, R, alpha(sig, 0.8), R * 0.5);
    } else if (playing && s.rs == ReactionModel.waiting) {
      final k = 0.5 + 0.5 * math.sin(s.time * 3);
      canvas.drawCircle(c, R * (1.08 + 0.05 * k), Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = alpha(const Color(0xFFFF4D6A), 0.35 + 0.3 * k));
    }
    canvas.drawCircle(c, R + 6, Paint()..color = Colors.white);
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
    if (playing && s.rs == ReactionModel.decoy) {
      paintText(canvas, '!', c, size: R * 1.1, color: Colors.white);
    } else if (playing && s.rs == ReactionModel.go) {
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
