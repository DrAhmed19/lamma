import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/loop.dart';
import '../core/sfx.dart';
import '../logic/spy_bank.dart';
import '../logic/spy_logic.dart';
import '../net/room.dart';
import '../net/session.dart';
import '../ui/kit.dart';
import '../ui/online.dart';
import '../ui/art.dart';
import '../ui/theme.dart';

/// الجاسوس: الكل يعرف المكان إلا الجاسوس، ويسألون بعض بالصوت (جالسين سوا).
/// التطبيق يدير الدور والوقت والتصويت. القواعد بـ SpyModel، والسيرفر يخفي الأسرار.
class SpyGame extends StatefulWidget {
  const SpyGame({super.key, required this.room});
  final RoomConn room;

  @override
  State<SpyGame> createState() => _SpyState();
}

const _red = Color(0xFFFF4D6A);
const _gold = Color(0xFFFFD34D);
const _green = Color(0xFF5CE08A);

class _SpyState extends LoopState<SpyGame> {
  late final OnlineSession<SpyModel> session = OnlineSession<SpyModel>(widget.room);

  SpyModel get m => session.model;
  @override
  bool get ready => session.ready;
  int get me => session.me;

  /// صوتي قبل ما يرجع من السيرفر
  int picked = -1;

  /// دوري ظاهر؟ (حتى ما يشوفه اللي جنبك)
  bool show = true;

  /// شبكة حزرة المكان مفتوحة (للجاسوس بوقت اللعب)
  bool guessOpen = false;
  int _lastTick = -1;
  String _sig = '';

  @override
  void initState() {
    super.initState();
    Sfx.preload(const ['pop', 'whoosh', 'clack', 'tada', 'tick', 'win']);
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  void restart() {
    if (!m.over) return;
    session.again();
  }

  bool get _isSpy => me >= 0 && m.spies.contains(me);
  bool get _playing => me >= 0 && !m.out[me];

  @override
  void update(double dt) {
    session.update(dt);
    for (final e in session.takeEvents()) {
      switch (e['e']) {
        case 'play':
          show = false;
          Sfx.play('whoosh', volume: 0.5);
        case 'ask':
          Sfx.play('pop', volume: 0.5);
          if (e['to'] == me) Fx.mid();
        case 'call':
          picked = -1;
          guessOpen = false;
          _lastTick = -1;
          Sfx.play('whoosh', volume: 0.6);
          Fx.mid();
        case 'voted':
          Sfx.play('clack', volume: 0.25);
        case 'found':
          Sfx.play('tada', volume: 0.7);
        case 'result':
          guessOpen = false;
          Sfx.play(m.spiesWin == _isSpy ? 'win' : 'tick');
          Fx.big();
        case 'again':
          show = true;
          picked = -1;
          guessOpen = false;
      }
    }
    if (!ready) return;
    if (m.phase == 'vote' && _playing && _myVote < 0) {
      final left = m.timeLeft.ceil();
      if (left <= 5 && left > 0 && left != _lastTick) {
        _lastTick = left;
        Sfx.play('tick', volume: 0.5);
      }
    }
    final sig = '${m.phase}|${m.turn}|${m.prev}|${m.votes}|${m.out}|${m.round}|${m.result}|${m.timeLeft.ceil()}|$show|$guessOpen|$picked|${m.place}|${m.spies}';
    if (sig != _sig) {
      _sig = sig;
      setState(() {});
    }
  }

  int get _myVote => picked >= 0 ? picked : (me >= 0 ? m.votes[me] : -1);

  void _ask(int p) {
    if (!ready || paused || m.phase != 'play' || me != m.turn) return;
    session.input(me, {'a': 'ask', 't': p});
    Fx.tap();
  }

  void _vote(int p) {
    if (!ready || paused || !_playing || m.phase != 'vote' || p == me || m.out[p]) return;
    setState(() => picked = p);
    session.input(me, {'a': 'vote', 't': p});
    Fx.tap();
  }

  void _guess(int idx) {
    session.input(me, {'a': 'guess', 't': idx});
    setState(() => guessOpen = false);
    Fx.tap();
  }

  // ------------------------------------------------------------ مساعدات

  String _name(int p) => p == me ? 'أنت' : session.nameOf(p);
  Color _colorOf(int p) {
    final room = widget.room;
    return C.players[(p < room.seats.length ? room.seats[p] : p) % C.players.length];
  }

  String _avatarOf(int p) {
    final room = widget.room;
    return p < room.seats.length ? room.avatarOfSeat(room.seats[p]) : '';
  }

  String _clock(double s) {
    final t = s.ceil();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  String get _placeName => m.place >= 0 && m.place < spyBank.length ? spyBank[m.place] : '';
  String _spyNames() => m.spies.map(session.nameOf).join(' و ');

  String get _resultText {
    final sp = _spyNames();
    final guess = m.guess >= 0 && m.guess < spyBank.length ? spyBank[m.guess] : 'لا شيء';
    switch (m.result) {
      case 'early_ok':
        return 'الجاسوس $sp عرف المكان «$_placeName» وفاز!';
      case 'early_wrong':
        return 'حزر الجاسوس $sp «$guess» لكن المكان «$_placeName». فاز الباقون!';
      case 'found_ok':
        return 'كشفوا الجاسوس ${session.nameOf(m.accused)} لكنه حزر المكان «$_placeName» وفاز!';
      case 'found_wrong':
        return 'كشفوا الجاسوس ${session.nameOf(m.accused)} ولم يحزر المكان «$_placeName». فاز الباقون!';
      case 'innocent':
        return 'اتهموا ${session.nameOf(m.accused)} وهو بريء. الجاسوس $sp ينجو ويفوز!';
      case 'nomajority':
        return 'لم يتفقوا على أحد. الجاسوس $sp ينجو ويفوز!';
      case 'spy_left':
        return 'خرج الجاسوس. فاز الباقون.';
      default:
        return 'انتهت اللعبة بخروج اللاعبين.';
    }
  }

  // ------------------------------------------------------------ الواجهة

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      onPause: openPause,
      room: widget.room,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment(0, -0.5), radius: 1.2, colors: [Color(0xFF3A1B2E), C.bg]),
              ),
            ),
          ),
          if (!ready)
            const NetWaiting()
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(60, 8, 12, 10),
                child: m.over
                    ? _endPanel()
                    : Column(
                        children: [
                          _header(),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _roleCard(),
                                    const SizedBox(height: 10),
                                    _banner(),
                                    const SizedBox(height: 8),
                                    _players(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _actions(),
                        ],
                      ),
              ),
            ),
          if (ready) NetBanner(session: session, players: m.players),
          if (ready && !m.over && _playing && ((m.phase == 'guess' && m.guessBy == me) || (m.phase == 'play' && guessOpen && _isSpy)))
            Positioned.fill(child: _guessPanel()),
        ],
      ),
    );
  }

  Widget _header() {
    final title = switch (m.phase) {
      'count' => 'الجاسوس',
      'play' => 'اسألوا بعض!',
      'vote' => 'من هو الجاسوس؟',
      _ => 'الجاسوس يحزر المكان',
    };
    return Column(
      children: [
        Row(
          children: [
            Text('الجولة ${m.round}', style: body(14, color: C.muted, weight: FontWeight.w700)),
            const Spacer(),
            if (m.phase != 'count') Text(_clock(m.timeLeft), style: body(18, color: m.timeLeft < 15 ? _red : _gold, weight: FontWeight.w800)),
          ],
        ),
        Text(title, style: display(m.phase == 'count' ? 40 : 30, shadows: [Shadow(color: alpha(C.accent, 0.6), blurRadius: 18)])),
      ],
    );
  }

  Widget _roleCard() {
    final spy = _isSpy;
    final String big, small;
    if (me < 0 || m.out[me]) {
      big = 'أنت تتفرّج';
      small = '';
    } else if (!show) {
      big = 'اضغط لإظهار دورك';
      small = 'تأكد أنه لا أحد ينظر إلى هاتفك';
    } else if (spy) {
      big = 'أنت الجاسوس 🕵️';
      small = 'اعرف المكان من أسئلتهم، ولا تدعهم يكشفونك';
    } else {
      big = 'المكان: $_placeName';
      small = 'ابحث عن الجاسوس ولا تفضح المكان';
    }
    final on = show && _playing;
    return GestureDetector(
      onTap: _playing ? () => setState(() => show = !show) : null,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: alpha(on && spy ? _red : C.accent, 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: alpha(on && spy ? _red : C.accent, 0.8), width: 2),
        ),
        child: Column(
          children: [
            Text(big, textAlign: TextAlign.center, style: display(on ? 28 : 20, color: on && spy ? _red : Colors.white)),
            if (small.isNotEmpty) Text(small, textAlign: TextAlign.center, style: body(13, color: C.muted)),
          ],
        ),
      ),
    );
  }

  Widget _banner() {
    String t;
    switch (m.phase) {
      case 'count':
        t = 'استعدّوا... سيبدأ السؤال بعد قليل';
      case 'play':
        t = m.turn == me
            ? 'دورك! اسأل أحدًا بصوتك ثم اضغط عليه'
            : 'الدور على ${session.nameOf(m.turn)}${m.prev >= 0 ? ' (سأله ${_name(m.prev)})' : ''}';
      case 'vote':
        t = !_playing ? 'تتفرّج' : (_myVote < 0 ? 'اضغط على من تظنّه الجاسوس' : 'سُجّل صوتك، ويمكنك تغييره');
      default:
        t = m.guessBy == me ? 'اختر المكان (حزرة واحدة)' : 'انتظروا... ${session.nameOf(m.guessBy)} يحزر المكان';
    }
    return Text(t, textAlign: TextAlign.center, style: body(16, weight: FontWeight.w800));
  }

  Widget _players() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [for (final p in m.alive) _chip(p)],
    );
  }

  Widget _chip(int p) {
    final col = _colorOf(p);
    final isTurn = m.phase == 'play' && m.turn == p;
    final canAsk = m.phase == 'play' && me == m.turn && p != me && !(p == m.prev && m.alive.length > 2);
    final canVote = m.phase == 'vote' && _playing && p != me;
    final chosen = m.phase == 'vote' && _myVote == p;
    final voted = m.phase == 'vote' && m.votes[p] != -1;
    final onTap = canAsk ? () => _ask(p) : (canVote ? () => _vote(p) : null);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: alpha(col, chosen || isTurn ? 0.32 : 0.15),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: alpha(chosen ? _red : (isTurn ? _gold : col), chosen || isTurn ? 1 : 0.45), width: chosen || isTurn ? 3 : 1.5),
          boxShadow: isTurn ? [BoxShadow(color: alpha(_gold, 0.4), blurRadius: 16)] : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: alpha(col, 0.25), shape: BoxShape.circle, border: Border.all(color: col, width: 2)),
              child: Avatar(_avatarOf(p), size: 28),
            ),
            const SizedBox(height: 4),
            Text(p == me ? '${session.nameOf(p)} (أنت)' : session.nameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(12, weight: FontWeight.w800)),
            SizedBox(
              height: 16,
              child: voted
                  ? Text('صوّت', style: body(11, color: _green, weight: FontWeight.w700))
                  : (isTurn ? Text('يسأل', style: body(11, color: _gold, weight: FontWeight.w700)) : null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    if (!_playing || m.phase != 'play') return const SizedBox(height: 4);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        BigButton(label: 'اطلب التصويت', icon: Icons.how_to_vote_rounded, onTap: () => session.input(me, {'a': 'call'})),
        if (_isSpy) BigButton(label: 'عرفت المكان', icon: Icons.place_rounded, filled: false, onTap: () => setState(() => guessOpen = true)),
      ],
    );
  }

  /// شبكة خيارات المكان (للجاسوس)
  Widget _guessPanel() {
    return Container(
      color: alpha(const Color(0xFF05070F), 0.9),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(60, 12, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('أين نحن؟', style: display(34, color: _gold)),
                  Text(m.phase == 'guess' ? 'حزرة واحدة فقط!' : 'حزرة واحدة: إن أخطأت يفوز الباقون', style: body(13, color: C.muted)),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final i in m.opts)
                        GestureDetector(
                          onTap: () => _guess(i),
                          child: Container(
                            width: 104,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            decoration: BoxDecoration(
                              color: alpha(C.accent, 0.2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: alpha(C.accent, 0.8), width: 1.5),
                            ),
                            child: Text(spyBank[i], textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                  if (m.phase == 'play') ...[
                    const SizedBox(height: 10),
                    BigButton(label: 'رجوع', filled: false, onTap: () => setState(() => guessOpen = false)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// النتيجة
  Widget _endPanel() {
    final order = List.of(m.alive)..sort((a, b) => m.total[b].compareTo(m.total[a]));
    final won = me >= 0 && m.isWinner(me);
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(m.result == 'abort' ? 'انتهت اللعبة' : (won ? 'فزت!' : 'الجولة ${m.round}'), style: display(40, color: _gold)),
              const SizedBox(height: 6),
              Text(_resultText, textAlign: TextAlign.center, style: body(16, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('الجاسوس: ${_spyNames()}  •  المكان: $_placeName', textAlign: TextAlign.center, style: body(13, color: C.muted)),
              const SizedBox(height: 10),
              for (final p in order)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: alpha(_colorOf(p), p == me ? 0.26 : 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: alpha(m.spies.contains(p) ? _red : _colorOf(p), 0.7)),
                  ),
                  child: Row(
                    children: [
                      Avatar(_avatarOf(p), size: 28),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p == me ? '${session.nameOf(p)} (أنت)' : session.nameOf(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(14, weight: FontWeight.w800))),
                      if (m.spies.contains(p)) Text('🕵️ ', style: body(14)),
                      Text('${m.total[p]}', style: display(22, color: _gold)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  BigButton(label: againLabelOf(session) ?? 'العب مرة أخرى', icon: Icons.replay_rounded, onTap: restart),
                  BigButton(label: 'الغرفة', filled: false, onTap: roomMenu(context, session) ?? () => Navigator.of(context).pop()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// أيقونة اللعبة: قبعة ونظارة
class SpyIcon extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // وجه
    canvas.drawCircle(Offset(w * 0.5, h * 0.62), w * 0.22, Paint()..color = const Color(0xFFFFD9B0));
    // قبعة
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.42), width: w * 0.72, height: h * 0.14), Paint()..color = const Color(0xFF222222));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.5, h * 0.3), width: w * 0.4, height: h * 0.26), Radius.circular(w * 0.06)), Paint()..color = const Color(0xFF2E2E2E));
    // نظارة
    final g = Paint()..color = Colors.black;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.4, h * 0.6), width: w * 0.16, height: h * 0.1), Radius.circular(4)), g);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.6, h * 0.6), width: w * 0.16, height: h * 0.1), Radius.circular(4)), g);
  }

  @override
  bool shouldRepaint(SpyIcon old) => false;
}
