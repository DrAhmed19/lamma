import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../logic/quiz_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/theme.dart';

/// سؤال وجواب: 2-4 لاعبين. القواعد بـ QuizModel (نفسها بالسيرفر).
/// على جهاز واحد: الشاشة نصّين (اللي فوق مقلوب)، وكل لاعب إله أزراره.
class QuizGame extends StatefulWidget {
  const QuizGame({super.key, required this.players, this.room});
  final int players;
  final RoomConn? room;

  @override
  State<QuizGame> createState() => _QuizState();
}

const _letters = ['أ', 'ب', 'ج', 'د'];

class _QuizState extends LoopState<QuizGame> {
  late final Session<QuizModel> session = widget.room != null
      ? OnlineSession<QuizModel>(widget.room!)
      : LocalSession(QuizModel(players: widget.players, crazy: false, seed: DateTime.now().microsecondsSinceEpoch));

  QuizModel get m => session.model;
  bool get ready => session is! OnlineSession || (session as OnlineSession).ready;
  bool get online => session.online;
  double endAt = 0;
  bool showOver = false;

  @override
  void initState() {
    super.initState();
    Sfx.preload(const ['pop', 'tick', 'win', 'hit']);
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
        case 'q':
          Sfx.play('pop', volume: 0.5);
        case 'ans':
          if (!online || e['p'] == session.me) Fx.tap();
        case 'reveal':
          final good = online ? m.answers[math.max(0, session.me)] == e['c'] : true;
          if (good) {
            Fx.mid();
          } else {
            Fx.hit();
          }
        case 'win':
          endAt = time;
          Fx.big();
          Sfx.play('win');
        case 'again':
          showOver = false;
          setState(() {});
      }
    }
    if (!ready) return;
    final shouldShow = m.over && time - endAt > 0.8;
    if (shouldShow != showOver) setState(() => showOver = shouldShow);
  }

  void _answer(int p, int a) {
    if (!ready || m.counting || m.over || m.reveal || paused || m.answers[p] >= 0) return;
    session.input(p, {'m': 'ans', 'a': a});
  }

  String _name(int p) => online ? session.nameOf(p) : C.playerNames[p];

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      child: !ready
          ? const NetWaiting()
          : Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1A1240), Color(0xFF0B0A24)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ValueListenableBuilder<int>(
                    valueListenable: frame,
                    builder: (context, _, __) => m.counting ? const SizedBox() : (online ? _onlineView() : _localView()),
                  ),
                ),
                if (m.counting)
                  Positioned.fill(
                    child: Countdown(key: ValueKey('${m.startAt}'), paused: paused && !online, dual: !online, onDone: () {}),
                  ),
                if (online) NetBanner(session: session, players: m.players),
                if (showOver)
                  Positioned.fill(
                    child: ResultOverlay(
                      winner: m.winner,
                      scores: m.score,
                      dual: !online,
                      menuLabel: online ? 'الغرفة' : null,
                      onMenu: roomMenu(context, session),
                      names: namesOf(session),
                      againLabel: againLabelOf(session),
                      footer: tourFooter(session),
                      onAgain: restart,
                    ),
                  ),
              ],
            ),
    );
  }

  // ------------------------------------------------------------ أونلاين: الشاشة كلها إلي

  Widget _onlineView() {
    final me = session.me;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(60, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _scoreRow(),
            const SizedBox(height: 12),
            _progress(),
            const Spacer(),
            _questionCard(big: true),
            const Spacer(),
            for (var a = 0; a < 4; a++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _option(me, a, height: 60, fontSize: 19),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scoreRow() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var p = 0; p < m.players; p++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: alpha(C.players[p], 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: alpha(C.players[p], m.answers[p] >= 0 && !m.reveal ? 1 : 0.4), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_name(p), style: body(14, weight: FontWeight.w800)),
                const SizedBox(width: 8),
                Text('${m.score[p]}', style: display(20, color: C.players[p])),
                if (m.answers[p] >= 0 && !m.reveal) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle_rounded, size: 16, color: C.players[p]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _progress() {
    final f = m.reveal ? 0.0 : m.timeLeft / QuizModel.askTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('السؤال ${m.qi + 1} من ${QuizModel.questions}', textAlign: TextAlign.center, style: body(14, color: C.muted)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 8,
            backgroundColor: alpha(Colors.white, 0.08),
            color: f < 0.3 ? const Color(0xFFFF4D6A) : const Color(0xFF8B6CFF),
          ),
        ),
      ],
    );
  }

  Widget _questionCard({bool big = false}) {
    final q = m.current;
    return Container(
      padding: EdgeInsets.all(big ? 22 : 12),
      decoration: BoxDecoration(
        color: alpha(Colors.white, 0.07),
        borderRadius: BorderRadius.circular(big ? 24 : 18),
        border: Border.all(color: alpha(Colors.white, 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(q.$1, textAlign: TextAlign.center, style: body(big ? 24 : 16, weight: FontWeight.w800)),
          if (m.reveal && m.fastest >= 0) ...[
            const SizedBox(height: 8),
            Text('أسرع إجابة صحيحة: ${_name(m.fastest)} (+1)',
                textAlign: TextAlign.center, style: body(big ? 15 : 12, color: C.players[m.fastest], weight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  /// زر جواب للاعب p
  Widget _option(int p, int a, {double height = 48, double fontSize = 15}) {
    final q = m.current;
    final mine = p >= 0 && m.answers[p] == a;
    final correct = q.$3 == a;
    var bg = alpha(Colors.white, 0.08);
    var border = alpha(Colors.white, 0.18);
    if (m.reveal) {
      if (correct) {
        bg = alpha(C.go, 0.35);
        border = C.go;
      } else if (mine) {
        bg = alpha(const Color(0xFFFF4D6A), 0.3);
        border = const Color(0xFFFF4D6A);
      }
    } else if (mine) {
      bg = alpha(C.players[p], 0.35);
      border = C.players[p];
    }
    final locked = p < 0 || m.reveal || m.answers[p] >= 0;
    // دائرة الحرف: إذا الارتفاع مفتوح (جهاز واحد) حجم ثابت
    final dot = height.isFinite ? height * 0.6 : 30.0;
    return Pressable(
      onTap: locked ? null : () => _answer(p, a),
      scale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1.6),
        ),
        child: Row(
          children: [
            Container(
              width: dot,
              height: dot,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: alpha(Colors.white, 0.12), shape: BoxShape.circle),
              child: Text(_letters[a], style: body(math.min(fontSize * 0.9, dot * 0.55), weight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(q.$2[a], maxLines: 2, overflow: TextOverflow.ellipsis, style: body(fontSize, weight: FontWeight.w700)),
            ),
            if (m.reveal && correct) const Icon(Icons.check_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ جهاز واحد: نصّين متقابلين

  Widget _localView() {
    final bottom = [0, if (m.players > 2) 2];
    final top = [1, if (m.players > 3) 3];
    return Column(
      children: [
        Expanded(child: RotatedBox(quarterTurns: 2, child: _half(top))),
        Container(height: 2, color: alpha(Colors.white, 0.1)),
        Expanded(child: _half(bottom)),
      ],
    );
  }

  Widget _half(List<int> ps) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _progress(),
          const SizedBox(height: 8),
          _questionCard(),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in ps)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: C.players[p], shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text('${_name(p)}: ${m.score[p]}', style: body(13, weight: FontWeight.w800, color: C.players[p])),
                            ],
                          ),
                          const SizedBox(height: 4),
                          for (var a = 0; a < 4; a++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: _option(p, a, height: double.infinity, fontSize: ps.length > 1 ? 12.5 : 15),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// أيقونة سؤال وجواب
class QuizIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final bubble = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.12, h * 0.14, w * 0.76, h * 0.58), Radius.circular(w * 0.16));
    canvas.drawRRect(bubble, Paint()..color = Colors.white);
    final tail = Path()
      ..moveTo(w * 0.3, h * 0.7)
      ..lineTo(w * 0.26, h * 0.88)
      ..lineTo(w * 0.46, h * 0.72)
      ..close();
    canvas.drawPath(tail, Paint()..color = Colors.white);
    final tp = TextPainter(
      text: TextSpan(text: '؟', style: TextStyle(fontSize: h * 0.46, color: const Color(0xFF6A3DE8), fontWeight: FontWeight.w900)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset(w * 0.5 - tp.width / 2, h * 0.43 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
