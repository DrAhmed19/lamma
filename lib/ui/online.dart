import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../games/registry.dart';
import '../net/room.dart';
import '../net/session.dart';
import 'background.dart';
import 'kit.dart';
import 'theme.dart';

/// شاشة الدخول للأونلاين: تسوّي غرفة أو تدخل بكود
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key, this.game, this.code});

  /// اللعبة اللي جاي منها (صاحب الغرفة يختارها تلقائياً)
  final GameInfo? game;
  final String? code;

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  late final _name = TextEditingController(text: playerName);
  late final _code = TextEditingController(text: widget.code ?? '');
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _cleanName => _name.text.trim().isEmpty ? 'لاعب' : _name.text.trim();

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final code = await RoomConn.createRoom();
      if (!mounted) return;
      _enter(code);
    } catch (_) {
      setState(() => _err = 'ما گدرنا نوصل للسيرفر. تأكد من النت وجرّب مرة ثانية.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _join() {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 4) {
      setState(() => _err = 'الكود 4 حروف');
      return;
    }
    _enter(code);
  }

  void _enter(String code) {
    playerName = _cleanName;
    final room = RoomConn.join(code, playerName);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => LobbyScreen(room: room, preferGame: widget.game),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: LammaBackground()),
          SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(sidePad(context), 8, sidePad(context), 24),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    Text('أونلاين', style: display(34)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('كل واحد يلعب بتلفونه من أي مكان. سوّي غرفة وانطي الكود لربعك.',
                    style: body(15, color: C.muted)),
                const SizedBox(height: 22),
                if (!onlineAvailable)
                  _note('الأونلاين بعده مو مفعّل بهالنسخة. حدّث التطبيق أو جرّب الويب.')
                else ...[
                  Text('اسمك', style: body(15, weight: FontWeight.w700, color: C.muted)),
                  const SizedBox(height: 8),
                  _field(_name, hint: 'شسمك؟', maxLength: 14),
                  const SizedBox(height: 22),
                  BigButton(
                    label: _busy ? 'لحظة...' : 'سوّي غرفة جديدة',
                    icon: Icons.add_rounded,
                    onTap: _busy ? () {} : _create,
                  ),
                  const SizedBox(height: 26),
                  Text('عندك كود؟', style: body(15, weight: FontWeight.w700, color: C.muted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _field(_code, hint: 'ABCD', maxLength: 4, code: true)),
                      const SizedBox(width: 10),
                      BigButton(label: 'ادخل', icon: Icons.login_rounded, filled: false, onTap: _join),
                    ],
                  ),
                  if (_err != null) ...[
                    const SizedBox(height: 16),
                    _note(_err!, color: const Color(0xFFFF4D6A)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, {required String hint, int? maxLength, bool code = false}) {
    return TextField(
      controller: c,
      maxLength: maxLength,
      textAlign: code ? TextAlign.center : TextAlign.start,
      textCapitalization: code ? TextCapitalization.characters : TextCapitalization.none,
      inputFormatters: code ? [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')), _Upper()] : null,
      style: code ? display(28, color: Colors.white) : body(18, weight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: body(18, color: alpha(C.muted, 0.5)),
        filled: true,
        fillColor: alpha(Colors.white, 0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.line)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: alpha(C.accent, 0.8))),
      ),
    );
  }
}

class _Upper extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}

Widget _note(String text, {Color color = C.muted}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: alpha(color, 0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: alpha(color, 0.4)),
    ),
    child: Text(text, style: body(15, color: Colors.white)),
  );
}

/// شاشة الغرفة: الكود، اللاعبين، وصاحب الغرفة يختار اللعبة ويبدي
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.room, this.preferGame});
  final RoomConn room;
  final GameInfo? preferGame;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  RoomConn get room => widget.room;
  int _shownRound = -1;
  bool _gameOpen = false;
  bool _cfgSent = false;
  ModalRoute<dynamic>? _self;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _self ??= ModalRoute.of(context);
  }

  static List<GameInfo> get onlineGames => games.where((g) => g.online != null).toList();

  StreamSubscription<NetNotice>? _noticeSub;

  @override
  void initState() {
    super.initState();
    room.addListener(_onRoom);
    _noticeSub = room.notices.listen(_onNotice);
  }

  @override
  void dispose() {
    _noticeSub?.cancel();
    room.removeListener(_onRoom);
    room.leave();
    room.dispose();
    super.dispose();
  }

  /// تنبيهات الغرفة تطلع كشريط تحت (حتى وانت باللعبة)
  void _onNotice(NetNotice n) {
    if (!mounted) return;
    final me = n.seat == room.mySeat;
    final text = switch (n.kind) {
      'joined' => 'دخل ${n.name}',
      'left' => 'طلع ${n.name} من الغرفة',
      'kicked' => 'انطرد ${n.name}',
      'quit' => '${n.name} طلع من اللعبة',
      'host' => me ? 'صرت انت صاحب الغرفة' : '${n.name} صار صاحب الغرفة',
      _ => null,
    };
    if (text == null || (me && n.kind != 'host')) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: C.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: C.line)),
        content: Text(text, style: body(15, weight: FontWeight.w700, color: Colors.white)),
      ));
  }

  /// قائمة صاحب الغرفة على كل لاعب: يسلّمه الغرفة أو يطرده
  Future<void> _seatMenu(NetPlayer p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: C.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name, textAlign: TextAlign.center, style: display(28)),
            const SizedBox(height: 14),
            if (p.on) ...[
              BigButton(
                label: 'خليه صاحب الغرفة',
                icon: Icons.star_rounded,
                filled: false,
                onTap: () => Navigator.pop(ctx, 'host'),
              ),
              const SizedBox(height: 10),
            ],
            BigButton(
              label: 'اطرده من الغرفة',
              icon: Icons.block_rounded,
              color: const Color(0xFFFF4D6A),
              onTap: () => Navigator.pop(ctx, 'kick'),
            ),
          ],
        ),
      ),
    );
    if (action == 'host') room.makeHost(p.seat);
    if (action == 'kick') room.kick(p.seat);
  }

  void _onRoom() {
    if (!mounted) return;
    // صاحب الغرفة: نختار اللعبة اللي جاي منها
    if (room.isHost && !_cfgSent && room.game == null) {
      _cfgSent = true;
      final g = widget.preferGame?.online != null ? widget.preferGame! : onlineGames.first;
      room.setGame(g.id, false);
    }
    // بدت مباراة وأني بيها → نفتح اللعبة
    if (room.started && room.me >= 0 && room.round != _shownRound && !_gameOpen) {
      _shownRound = room.round;
      _openGame();
    }
    // صاحب الغرفة رجّع الكل → نسد اللعبة
    if (!room.started && _gameOpen) {
      Navigator.of(context).popUntil((r) => r == _self || r.isFirst);
    }
    setState(() {});
  }

  Future<void> _openGame() async {
    final g = games.where((x) => x.id == room.game).firstOrNull;
    if (g?.online == null) return;
    _gameOpen = true;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => g!.online!(room)));
    _gameOpen = false;
    if (!mounted) return;
    // صاحب الغرفة طلع من شاشة النتيجة → الكل يرجع للغرفة
    if (room.isHost && room.started && (room.state?.model.over ?? true)) room.toLobby();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: LammaBackground()),
            SafeArea(
              child: ListenableBuilder(
                listenable: room,
                builder: (context, _) => _body(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (room.status == RoomStatus.closed && room.error != null) {
      final msg = switch (room.error) {
        'notfound' => 'ما لگينا غرفة بهالكود. تأكد منه.',
        'full' => 'الغرفة مليانة (4 لاعبين).',
        'kicked' => 'صاحب الغرفة طلّعك من الغرفة.',
        _ => 'صار خلل بالاتصال.',
      };
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _note(msg, color: const Color(0xFFFF4D6A)),
            const SizedBox(height: 16),
            BigButton(label: 'رجوع', onTap: () => Navigator.of(context).pop()),
          ],
        ),
      );
    }

    final chosen = games.where((g) => g.id == room.game).firstOrNull;
    final onCount = room.players.where((p) => p.on).length;
    final canStart = chosen != null && onCount >= chosen.minPlayers && onCount <= chosen.maxPlayers;

    return ListView(
      padding: EdgeInsets.fromLTRB(sidePad(context), 8, sidePad(context), 24),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ),
            const SizedBox(width: 4),
            Text('الغرفة', style: display(34)),
            const Spacer(),
            if (room.status != RoomStatus.online)
              Text(room.status == RoomStatus.connecting ? 'دا نتصل...' : 'دا نرجع نتصل...',
                  style: body(13, color: const Color(0xFFFFB627))),
          ],
        ),
        const SizedBox(height: 10),
        _codeCard(),
        const SizedBox(height: 20),
        Text('اللاعبين', style: body(15, weight: FontWeight.w700, color: C.muted)),
        const SizedBox(height: 8),
        for (var s = 0; s < 4; s++) _seat(s),
        if (room.isHost && room.players.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('اضغط على لاعب حتى تطرده أو تسلّمه الغرفة', style: body(13, color: C.muted)),
          ),
        if (!room.isHost && room.host >= 0 && !room.hostOn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _note('صاحب الغرفة انقطع... إذا ما رجع خلال ثواني، الغرفة تنتقل للي بعده.',
                color: const Color(0xFFFFB627)),
          ),
        const SizedBox(height: 20),
        if (room.started && room.me < 0)
          _note('أكو مباراة شغالة. تگدر تدخل بالجولة الجاية.')
        else if (room.started && room.me >= 0 && !_gameOpen)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _note(room.isHost ? 'المباراة بعدها مفتوحة.' : 'ننتظر صاحب الغرفة يرجّع الكل للغرفة...'),
              if (room.isHost) ...[
                const SizedBox(height: 12),
                BigButton(label: 'رجّع الكل للغرفة', icon: Icons.meeting_room_rounded, onTap: room.toLobby),
              ],
            ],
          )
        else if (room.isHost) ...[
          Text('اختار اللعبة', style: body(15, weight: FontWeight.w700, color: C.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in onlineGames) _gameChip(g, g.id == room.game),
            ],
          ),
          if (chosen?.crazyHowTo != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _modeChip('عادي', !room.crazy, () => room.setGame(chosen!.id, false))),
                const SizedBox(width: 8),
                Expanded(child: _modeChip('مجنون', room.crazy, () => room.setGame(chosen!.id, true))),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Opacity(
            opacity: canStart ? 1 : 0.45,
            child: BigButton(
              label: canStart ? 'ابدأ اللعب' : _needText(chosen, onCount),
              icon: Icons.play_arrow_rounded,
              color: chosen?.colors.first ?? C.accent,
              onTap: canStart ? room.start : () {},
            ),
          ),
        ] else
          _note(chosen == null
              ? 'ننتظر صاحب الغرفة يختار اللعبة...'
              : 'اللعبة: ${chosen.title}${room.crazy ? ' (مجنون)' : ''}\nننتظر صاحب الغرفة يبدي...'),
      ],
    );
  }

  String _needText(GameInfo? g, int on) {
    if (g == null) return 'اختار لعبة';
    if (on < g.minPlayers) return 'تحتاج ${g.minPlayers} لاعبين';
    return 'هاي اللعبة لـ ${g.maxPlayers} لاعبين بس';
  }

  /// رابط الدعوة يفتح الويب ويحط الكود (يشتغل للآيفون والأندرويد)
  String get _link => '${kIsWeb ? Uri.base.origin : kWebUrl}/?room=${room.code}';
  String get _invite => 'تعال العب وياي بلمّة 🎮\nكود الغرفة: ${room.code}\n$_link';

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: C.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: C.line)),
        content: Text(text, style: body(15, weight: FontWeight.w700, color: Colors.white)),
      ));
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _link));
      _toast('نسخت الرابط');
    } catch (_) {
      _toast('ما گدرت أنسخ. الكود: ${room.code}');
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(text: _invite));
    } catch (_) {
      await _copy();
    }
  }

  Widget _codeCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.line),
      ),
      child: Column(
        children: [
          Text('كود الغرفة', style: body(14, color: C.muted)),
          Text(room.code, style: display(54, color: Colors.white).copyWith(letterSpacing: 10)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _cardButton(Icons.share_rounded, 'شارك الدعوة', _share, filled: true)),
              const SizedBox(width: 8),
              Expanded(child: _cardButton(Icons.copy_rounded, 'انسخ الرابط', _copy)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardButton(IconData icon, String label, VoidCallback onTap, {bool filled = false}) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: filled ? alpha(C.accent, 0.28) : alpha(Colors.white, 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: filled ? alpha(C.accent, 0.8) : C.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: body(15, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _seat(int seat) {
    final p = room.players.where((x) => x.seat == seat).firstOrNull;
    final col = C.players[seat];
    final canManage = p != null && room.isHost && seat != room.mySeat;
    return Pressable(
      onTap: canManage ? () => _seatMenu(p) : null,
      scale: 0.98,
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: alpha(col, p == null ? 0.04 : 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: alpha(col, p == null ? 0.15 : 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: p == null ? alpha(col, 0.3) : col, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p == null ? 'فاضي' : '${p.name}${seat == room.mySeat ? ' (انت)' : ''}',
              style: body(17, weight: FontWeight.w800, color: p == null ? C.muted : Colors.white),
            ),
          ),
          if (p != null && seat == room.host) const Icon(Icons.star_rounded, color: Color(0xFFFFB627), size: 20),
          if (p != null && !p.on) ...[
            const SizedBox(width: 6),
            Text('انقطع', style: body(13, color: const Color(0xFFFF8A8A))),
          ],
          if (canManage) ...[
            const SizedBox(width: 6),
            const Icon(Icons.more_vert_rounded, color: C.muted, size: 20),
          ],
        ],
      ),
      ),
    );
  }

  Widget _gameChip(GameInfo g, bool selected) {
    return Pressable(
      onTap: () => room.setGame(g.id, false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? LinearGradient(colors: g.colors) : null,
          color: selected ? null : alpha(Colors.white, 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? alpha(Colors.white, 0.4) : C.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 28, height: 28, child: CustomPaint(painter: g.icon())),
            const SizedBox(width: 8),
            Text(g.title, style: body(16, weight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String label, bool selected, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? alpha(const Color(0xFFFF8A1F), 0.22) : alpha(Colors.white, 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? alpha(const Color(0xFFFF8A1F), 0.8) : C.line),
        ),
        child: Text(label, style: body(16, weight: FontWeight.w700)),
      ),
    );
  }
}

/// زر "الغرفة" بشاشة النتيجة أونلاين: صاحب الغرفة يرجّع الكل، والباقي يرجع لحاله
VoidCallback? roomMenu(BuildContext context, Session s) {
  if (s is! OnlineSession) return null;
  return () {
    if (s.room.isHost) {
      s.room.toLobby();
    } else {
      Navigator.of(context).pop();
    }
  };
}

/// بانتظار أول حالة من السيرفر
class NetWaiting extends StatelessWidget {
  const NetWaiting({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 14),
          Text('دا نتصل باللعبة...', style: body(16, color: C.muted)),
        ],
      ),
    );
  }
}

/// شريط فوگ اللعبة: إذا أني انقطعت، أو واحد من اللاعبين انقطع
class NetBanner extends StatelessWidget {
  const NetBanner({super.key, required this.session, required this.players});
  final Session session;
  final int players;

  @override
  Widget build(BuildContext context) {
    final s = session;
    if (s is! OnlineSession) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.paddingOf(context).top + 6,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: s.room,
          builder: (context, _) {
            String? text;
            if (s.room.status != RoomStatus.online) {
              text = 'انقطع النت... دا نرجع نتصل';
            } else {
              final gone = [for (var p = 0; p < players; p++) if (p != s.me && !s.isOn(p)) s.nameOf(p)];
              if (gone.isNotEmpty) text = '${gone.join('، ')} انقطع... اللعبة تكمل';
            }
            if (text == null) return const SizedBox.shrink();
            return Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: alpha(Colors.black, 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: alpha(const Color(0xFFFFB627), 0.6)),
                ),
                child: Text(text, style: body(14, weight: FontWeight.w700)),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// هامش جانبي: على الشاشات الكبيرة المحتوى يبقى بعرض مريح بالنص
double sidePad(BuildContext context, {double base = 20, double maxWidth = 560}) =>
    math.max(base, (MediaQuery.sizeOf(context).width - maxWidth) / 2);
