import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/profile.dart';
import '../games/registry.dart';
import '../net/lan.dart';
import '../net/room.dart';
import '../net/session.dart';
import 'background.dart';
import 'flow.dart' show createFriendsRoom;
import 'invite.dart';
import 'kit.dart';
import 'react.dart';
import 'share_card.dart';
import 'theme.dart';

Widget _note(String text, {Color color = C.muted, IconData? icon}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: alpha(color, 0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: alpha(color, 0.4)),
    ),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(text, style: body(15, color: Colors.white))),
      ],
    ),
  );
}

/// شاشة الغرفة: الدعوة، اللاعبين، وصاحب الغرفة يبدأ اللعب
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.room, this.preferGame, this.lanHost});
  final RoomConn room;
  final GameInfo? preferGame;

  /// إذا آني صاحب غرفة محلية: السيرفر شغّال بتلفوني
  final LanHost? lanHost;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  RoomConn get room => widget.room;
  int _shownRound = -1;
  bool _gameOpen = false;
  bool _cfgSent = false;
  ModalRoute<dynamic>? _self;
  StreamSubscription<NetNotice>? _noticeSub;
  AppLifecycleListener? _life;
  Timer? _clock;
  String? _tourCounted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _self ??= ModalRoute.of(context);
  }

  static List<GameInfo> get onlineGames => games.where((g) => g.online != null).toList();

  @override
  void initState() {
    super.initState();
    room.addListener(_onRoom);
    _noticeSub = room.notices.listen(_onNotice);
    // رجع للتطبيق (من الواتساب مثلاً): نتأكد إن الاتصال حي
    _life = AppLifecycleListener(onResume: room.wake);
    // عدّاد البداية التلقائية بالغرف العامة
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && room.autoAt != null && !_gameOpen) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _life?.dispose();
    _noticeSub?.cancel();
    room.removeListener(_onRoom);
    room.leave();
    room.dispose();
    final h = widget.lanHost;
    if (h != null) Future.delayed(const Duration(milliseconds: 300), h.stop);
    super.dispose();
  }

  /// صاحب الغرفة المحلية: الخروج يغلق الغرفة على الجميع، فنتأكد أولًا
  Future<void> _leave() async {
    if (widget.lanHost == null || room.players.length < 2) {
      Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('إغلاق الغرفة؟', style: display(26)),
        content: Text('الغرفة تعمل على هاتفك. إذا خرجت ستُغلق على الجميع.', style: body(15, color: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('البقاء', style: body(16, weight: FontWeight.w800))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('إغلاق', style: body(16, weight: FontWeight.w800, color: const Color(0xFFFF4D6A))),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  void _onNotice(NetNotice n) {
    if (!mounted || room.isPublic && n.kind == 'host') return;
    final me = n.seat == room.mySeat;
    final text = switch (n.kind) {
      'joined' => 'انضمّ ${n.name}',
      'left' => 'غادر ${n.name} الغرفة',
      'kicked' => 'تم إخراج ${n.name}',
      'quit' => 'خرج ${n.name} من اللعبة',
      'host' => me ? 'أصبحت أنت مدير الغرفة' : 'أصبح ${n.name} مدير الغرفة',
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

  Future<void> _seatMenu(NetPlayer p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(26), border: Border.all(color: C.line)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${p.avatar} ${p.name}', textAlign: TextAlign.center, style: display(28)),
            const SizedBox(height: 14),
            if (p.on) ...[
              BigButton(label: 'اجعله مدير الغرفة', icon: Icons.star_rounded, filled: false, onTap: () => Navigator.pop(ctx, 'host')),
              const SizedBox(height: 10),
            ],
            BigButton(
              label: 'إخراجه من الغرفة',
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
    // مدير الغرفة: نختار اللعبة اللي جاء منها
    if (room.isHost && !room.isPublic && !_cfgSent && room.game == null) {
      _cfgSent = true;
      final g = widget.preferGame?.online != null ? widget.preferGame! : onlineGames.first;
      room.setGame(g.id, false);
    }
    if (room.started && _gameOpen && !_closing) {
      if (!listEquals(room.seats, _openSeats) || room.game != _openGameId) {
        // تغيّر المشاركون أو اللعبة (بطولة): نغلق اللعبة ونفتحها من جديد
        _closing = true;
        Navigator.of(context).popUntil((r) => r == _self || r.isFirst);
      } else {
        _shownRound = room.round;
      }
    }
    // بدأت مباراة (أو جولة جديدة) وأنا فيها → نفتح اللعبة
    if (room.started && room.me >= 0 && room.round != _shownRound && !_gameOpen) {
      _shownRound = room.round;
      _openGame();
    }
    // مدير الغرفة أعاد الجميع → نغلق اللعبة
    if (!room.started && _gameOpen && !_closing) {
      _closing = true;
      Navigator.of(context).popUntil((r) => r == _self || r.isFirst);
    }
    // فزت بالبطولة؟
    final t = room.tour;
    if (t != null && t.done) {
      final key = '${t.games.join(',')}@${room.round}';
      if (_tourCounted != key) {
        _tourCounted = key;
        final r = t.ranking;
        if (r.isNotEmpty && r.first.key == room.mySeat && (r.length < 2 || r[1].value < r.first.value)) {
          Profile.I.recordTournamentWin();
        }
      }
    }
    setState(() {});
  }

  List<int> _openSeats = const [];
  String? _openGameId;
  bool _closing = false;

  Future<void> _openGame() async {
    final g = gameById(room.game);
    if (g?.online == null || _gameOpen) return;
    _gameOpen = true;
    _openSeats = List.of(room.seats);
    _openGameId = room.game;
    _shownRound = room.round;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => g!.online!(room)));
    _gameOpen = false;
    final closedByUs = _closing;
    _closing = false;
    if (!mounted) return;
    // مدير الغرفة خرج بنفسه من شاشة النتيجة → الجميع يعودون للغرفة
    if (!closedByUs && room.isHost && !room.isPublic && room.started && (room.state?.model.over ?? true)) room.toLobby();
    setState(() {});
    if (closedByUs) _onRoom();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.lanHost == null || room.players.length < 2,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
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
            if (room.status == RoomStatus.online && room.mySeat >= 0) ...[
              Positioned.fill(child: IgnorePointer(child: ReactLayer(room: room))),
              Positioned(left: 14, bottom: 14 + MediaQuery.paddingOf(context).bottom, child: ReactButton(room: room, size: 52)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (room.status == RoomStatus.closed && room.error != null) {
      final msg = switch (room.error) {
        'notfound' => 'انتهت هاي الغرفة، أو أن الرمز غير صحيح.',
        'full' => 'الغرفة ممتلئة.',
        'kicked' => 'أخرجك مدير الغرفة.',
        _ => room.isLan ? 'أُغلقت الغرفة.' : 'حدث خلل في الاتصال.',
      };
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _note(msg, color: const Color(0xFFFF4D6A), icon: Icons.error_outline_rounded),
            const SizedBox(height: 16),
            if (room.error == 'notfound' && !_local) ...[
              BigButton(
                label: 'سوّي غرفة جديدة',
                icon: Icons.add_rounded,
                onTap: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  createFriendsRoom(nav.context);
                },
              ),
              const SizedBox(height: 10),
            ],
            BigButton(label: 'رجوع', filled: room.error != 'notfound' || _local, onTap: () => Navigator.of(context).pop()),
          ],
        ),
      );
    }

    final chosen = gameById(room.game);
    return ListView(
      padding: EdgeInsets.fromLTRB(sidePad(context), 8, sidePad(context), 90),
      children: [
        _topBar(chosen),
        const GetAppBanner(padding: EdgeInsets.only(top: 4)),
        const SizedBox(height: 10),
        if (room.status != RoomStatus.online && room.mySeat < 0)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: NetWaiting())
        else ...[
          if (room.tour != null) ...[
            _tourCard(room.tour!),
            const SizedBox(height: 14),
          ],
          if (!room.isPublic) ...[
            _inviteCard(),
            const SizedBox(height: 18),
          ],
          _players(),
          const SizedBox(height: 18),
          _actions(chosen),
        ],
      ],
    );
  }

  Widget _topBar(GameInfo? chosen) {
    return Row(
      children: [
        IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white)),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.isPublic ? 'لعب مع الآخرين' : 'الغرفة', style: display(30)),
              if (room.status != RoomStatus.online)
                Text(room.status == RoomStatus.connecting ? 'جارٍ الاتصال...' : 'انقطع الاتصال، جارٍ إعادة الاتصال...',
                    style: body(13, color: const Color(0xFFFFB627)))
              else if (room.isLan)
                Text('بدون إنترنت · على شبكة Wi‑Fi نفسها', style: body(13, color: const Color(0xFF22D37E))),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ الدعوة

  String get _link {
    final lan = widget.lanHost?.joinUrl;
    if (lan != null) return lan;
    if (lanOrigin != null) return '$lanOrigin/?room=${room.code}&lan=1';
    return roomInviteLink(room.code);
  }

  /// غرفة محلية (بدون نت): الدعوة تبقى بالـ QR والرابط المحلي، بدون واتساب
  bool get _local => room.isLan || lanOrigin != null;

  String get _invite => _local
      ? 'تعال العب معي في لمّة 🎮\nافتح هذا الرابط وأنت على شبكة Wi‑Fi نفسها:\n$_link\nأو من التطبيق: انضمام ← الرمز ${room.code}'
      : roomInviteText(room.code, gameId: room.game);

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
      _toast('تم نسخ الرابط');
    } catch (_) {
      _toast('تعذّر النسخ. الرمز هو: ${room.code}');
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(text: _invite));
    } catch (_) {
      await _copy();
    }
  }

  void _showQr() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(room.code, style: display(40, color: Colors.white).copyWith(letterSpacing: 8)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: QrImageView(data: _link, size: 220, padding: EdgeInsets.zero),
              ),
              const SizedBox(height: 12),
              Text(
                room.isLan ? 'امسح الرمز بكاميرا الهاتف (يجب أن تكونوا على شبكة Wi‑Fi نفسها)' : 'امسح الرمز بكاميرا الهاتف',
                textAlign: TextAlign.center,
                style: body(14, color: C.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _square(IconData icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: alpha(Colors.white, 0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
          child: Icon(icon, color: Colors.white),
        ),
      );

  // بطاقة الدعوة مضغوطة: الرمز + أزرار بسطر، والـ QR بنافذة لمّن ينضغط
  Widget _inviteCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: C.line)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رمز الغرفة', style: body(13, color: C.muted)),
                    Text(room.code, style: display(40, color: Colors.white).copyWith(letterSpacing: 8, height: 1.1)),
                  ],
                ),
              ),
              _square(Icons.copy_rounded, _copy),
              const SizedBox(width: 8),
              _square(Icons.qr_code_2_rounded, _showQr),
            ],
          ),
          const SizedBox(height: 10),
          if (!_local)
            Row(
              children: [
                Expanded(child: WhatsAppButton(label: 'واتساب', text: () => _invite)),
                const SizedBox(width: 8),
                _square(Icons.share_rounded, _share),
              ],
            )
          else
            BigButton(label: 'إرسال الدعوة', icon: Icons.share_rounded, filled: true, onTap: _share),
          if (widget.lanHost != null) ...[
            const SizedBox(height: 8),
            Text('على شبكة Wi‑Fi نفسها · أبقِ التطبيق مفتوحًا طوال اللعب', textAlign: TextAlign.center, style: body(12, color: const Color(0xFFFFB627))),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ اللاعبون

  Widget _players() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('اللاعبون (${room.players.length})', style: body(15, weight: FontWeight.w800, color: C.muted)),
        const SizedBox(height: 8),
        for (final p in room.players) _seat(p),
        if (room.players.length < 2)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(room.isPublic ? 'جارٍ البحث عن لاعبين...' : 'بانتظار انضمام أصدقائك...', style: body(14, color: C.muted)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _seat(NetPlayer p) {
    final col = C.players[p.seat];
    final canManage = room.isHost && !room.isPublic && p.seat != room.mySeat;
    return Pressable(
      onTap: canManage ? () => _seatMenu(p) : null,
      scale: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: alpha(col, 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: alpha(col, 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: alpha(col, 0.25), shape: BoxShape.circle, border: Border.all(color: col, width: 2)),
              child: Text(p.avatar.isEmpty ? '🙂' : p.avatar, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${p.name}${p.seat == room.mySeat ? ' (أنت)' : ''}',
                style: body(17, weight: FontWeight.w800),
              ),
            ),
            if (p.seat == room.host && !room.isPublic) ...[
              const Icon(Icons.star_rounded, color: Color(0xFFFFB627), size: 20),
              const SizedBox(width: 2),
              Text('المدير', style: body(12, color: const Color(0xFFFFB627), weight: FontWeight.w700)),
            ],
            if (!p.on) ...[
              const SizedBox(width: 8),
              Text('غير متصل', style: body(12, color: const Color(0xFFFF8A8A))),
            ],
            if (canManage) const Icon(Icons.more_vert_rounded, color: C.muted, size: 20),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ البطولة

  Widget _tourCard(NetTour t) {
    final ranking = t.ranking;
    final champion = t.done && ranking.isNotEmpty ? ranking.first.key : -1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [alpha(const Color(0xFFFFB627), 0.22), alpha(const Color(0xFFFF8A1F), 0.08)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: alpha(const Color(0xFFFFB627), 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.done ? '🏆 انتهت البطولة' : '🏆 البطولة: اللعبة ${t.idx + 1} من ${t.games.length}',
              style: body(17, weight: FontWeight.w800)),
          if (champion >= 0) ...[
            const SizedBox(height: 4),
            Text('البطل: ${room.avatarOfSeat(champion)} ${room.nameOfSeat(champion)}', style: display(26, color: const Color(0xFFFFD34D))),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < ranking.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(width: 26, child: Text('${i + 1}', style: display(20, color: C.muted))),
                  Text(room.avatarOfSeat(ranking[i].key), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(room.nameOfSeat(ranking[i].key), style: body(15, weight: FontWeight.w700))),
                  Text('${ranking[i].value} نقطة', style: body(15, weight: FontWeight.w800, color: const Color(0xFFFFD34D))),
                ],
              ),
            ),
          if (ranking.isEmpty) Text('الفوز بأي لعبة = 3 نقاط، والتعادل = نقطة للجميع.', style: body(13, color: C.muted)),
          if (t.done && ranking.isNotEmpty) ShareResultButton(data: () => tourCard(room, t)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ البدء

  Widget _gameCard(GameInfo g, {VoidCallback? onChange}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [alpha(g.colors[0], 0.5), alpha(g.colors[1], 0.5)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: alpha(Colors.white, 0.18)),
      ),
      child: Row(
        children: [
          SizedBox(width: 52, height: 52, child: CustomPaint(painter: g.icon())),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, style: display(26)),
                Text(room.crazy && g.crazyHowTo != null ? 'الوضع المجنون' : g.tagline, style: body(13, color: alpha(Colors.white, 0.8))),
              ],
            ),
          ),
          if (onChange != null)
            TextButton(
              onPressed: onChange,
              child: Text('تغيير', style: body(15, weight: FontWeight.w800, color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _actions(GameInfo? chosen) {
    final onCount = room.players.where((p) => p.on).length;

    // مباراة جارية وأنا لست داخلها
    if (room.started && !_gameOpen) {
      if (room.me < 0) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _note('توجد مباراة جارية الآن. يمكنك مشاهدتها، وستشارك في الجولة القادمة.', icon: Icons.visibility_rounded),
            const SizedBox(height: 12),
            BigButton(label: 'مشاهدة المباراة', icon: Icons.visibility_rounded, filled: false, onTap: _openGame),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BigButton(
            label: room.playing ? 'العودة إلى اللعبة' : 'مشاهدة اللعبة',
            icon: Icons.sports_esports_rounded,
            color: chosen?.colors.first ?? C.accent,
            onTap: _openGame,
          ),
          if (room.isHost && !room.isPublic) ...[
            const SizedBox(height: 10),
            BigButton(label: 'إعادة الجميع إلى الغرفة', icon: Icons.meeting_room_rounded, filled: false, onTap: room.toLobby),
          ],
        ],
      );
    }

    // لعب سريع: يبدأ تلقائيًا
    if (room.isPublic) {
      final at = room.autoAt;
      final left = at == null ? null : math.max(0, at.difference(DateTime.now()).inMilliseconds / 1000).ceil();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chosen != null) _gameCard(chosen),
          const SizedBox(height: 12),
          _note(
            left != null ? 'تبدأ المباراة خلال $left ${left == 1 ? 'ثانية' : 'ثوانٍ'}...' : 'ستبدأ المباراة تلقائيًا عند انضمام لاعب آخر.',
            icon: Icons.timer_outlined,
          ),
        ],
      );
    }

    if (!room.isHost) {
      final host = room.nameOfSeat(room.host);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chosen != null) _gameCard(chosen),
          const SizedBox(height: 12),
          _note(
            room.host >= 0 && !room.hostOn ? 'انقطع اتصال $host. إذا لم يعد خلال لحظات ستنتقل الإدارة إلى غيره.' : 'بانتظار $host ليبدأ اللعب...',
            icon: Icons.hourglass_top_rounded,
          ),
        ],
      );
    }

    // مدير الغرفة
    final canStart = chosen != null && onCount >= chosen.minPlayers && onCount <= chosen.maxPlayers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chosen != null) _gameCard(chosen, onChange: () => _pickGame(onCount)),
        if (chosen?.crazyHowTo != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _modeChip('عادي', !room.crazy, () => room.setGame(chosen!.id, false))),
              const SizedBox(width: 8),
              Expanded(child: _modeChip('مجنون', room.crazy, () => room.setGame(chosen!.id, true))),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Opacity(
          opacity: canStart ? 1 : 0.5,
          child: BigButton(
            label: canStart ? 'ابدأ اللعب' : _needText(chosen, onCount),
            icon: Icons.play_arrow_rounded,
            color: chosen?.colors.first ?? C.accent,
            onTap: canStart ? room.start : () {},
          ),
        ),
        if (onCount >= 2) ...[
          const SizedBox(height: 10),
          BigButton(label: 'بطولة (عدة ألعاب)', icon: Icons.emoji_events_rounded, filled: false, onTap: () => _pickTour(onCount)),
        ],
        const SizedBox(height: 12),
        _capRow(),
      ],
    );
  }

  /// صاحب الغرفة يحدد أكثر عدد لاعبين (2-8، وما يقل عن الموجودين)
  Widget _capRow() {
    final lo = math.max(2, room.players.length);
    Widget btn(IconData icon, int to) {
      final ok = to >= lo && to <= 8;
      return Opacity(
        opacity: ok ? 1 : 0.35,
        child: Pressable(
          onTap: ok ? () => room.setCap(to) : null,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: alpha(Colors.white, 0.06), shape: BoxShape.circle, border: Border.all(color: C.line)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: alpha(Colors.white, 0.04), borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, color: C.muted, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text('أقصى عدد للاعبين', style: body(15, weight: FontWeight.w700))),
          btn(Icons.remove_rounded, room.cap - 1),
          SizedBox(width: 44, child: Text('${room.cap}', textAlign: TextAlign.center, style: display(26))),
          btn(Icons.add_rounded, room.cap + 1),
        ],
      ),
    );
  }

  String _needText(GameInfo? g, int on) {
    if (g == null) return 'اختر لعبة';
    if (on < g.minPlayers) return 'تحتاج إلى ${g.minPlayers == 2 ? 'لاعبَين' : '${g.minPlayers} لاعبين'} على الأقل';
    return 'هذه اللعبة لـ ${g.maxPlayers == 2 ? 'لاعبَين' : '${g.maxPlayers} لاعبين'} فقط';
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

  /// اختيار لعبة أخرى (تظهر الألعاب المناسبة لعدد اللاعبين أولًا)
  Future<void> _pickGame(int on) async {
    final pick = await showModalBottomSheet<GameInfo>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _sheet(
        title: 'اختر لعبة',
        child: Column(
          children: [
            for (final g in onlineGames)
              Opacity(
                opacity: on <= g.maxPlayers ? 1 : 0.4,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Pressable(
                    onTap: on <= g.maxPlayers ? () => Navigator.pop(ctx, g) : null,
                    child: _gameCard(g),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (pick != null) room.setGame(pick.id, false);
  }

  /// بطولة: اختيار الألعاب (2 إلى 6)
  Future<void> _pickTour(int on) async {
    final options = onlineGames.where((g) => g.maxPlayers >= on && g.minPlayers <= on).toList();
    final picked = <String>{for (final g in options.take(4)) g.id};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => _sheet(
          title: 'بطولة',
          subtitle: 'اختر الألعاب (من 2 إلى 6). الفوز بلعبة = 3 نقاط، والتعادل = نقطة.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in options)
                    Pressable(
                      onTap: () => set(() {
                        if (picked.contains(g.id)) {
                          picked.remove(g.id);
                        } else if (picked.length < 6) {
                          picked.add(g.id);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: picked.contains(g.id) ? LinearGradient(colors: g.colors) : null,
                          color: picked.contains(g.id) ? null : alpha(Colors.white, 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: picked.contains(g.id) ? alpha(Colors.white, 0.5) : C.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(picked.contains(g.id) ? Icons.check_circle_rounded : Icons.circle_outlined, size: 18, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(g.title, style: body(15, weight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Opacity(
                opacity: picked.length >= 2 ? 1 : 0.5,
                child: BigButton(
                  label: 'ابدأ البطولة (${picked.length} ألعاب)',
                  icon: Icons.emoji_events_rounded,
                  color: const Color(0xFFFF8A1F),
                  onTap: () {
                    if (picked.length >= 2) Navigator.pop(ctx, true);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) room.startTour([for (final g in options) if (picked.contains(g.id)) g.id]);
  }

  Widget _sheet({required String title, String? subtitle, required Widget child}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: C.line)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, textAlign: TextAlign.center, style: display(28)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, textAlign: TextAlign.center, style: body(14, color: C.muted)),
                ],
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================ أدوات تستعملها الألعاب

/// زر "الغرفة" بشاشة النتيجة أونلاين: المدير يعيد الجميع، والباقون يعودون وحدهم
VoidCallback? roomMenu(BuildContext context, Session s) {
  if (s is! OnlineSession) return null;
  return () {
    if (s.room.isHost && !s.room.isPublic) {
      s.room.toLobby();
    } else {
      Navigator.of(context).pop();
    }
  };
}

/// نص زر الإعادة: بالبطولة "اللعبة التالية"
String? againLabelOf(Session s) {
  if (s is! OnlineSession) return null;
  final t = s.room.tour;
  if (t == null) return null;
  if (t.done || t.idx >= t.games.length - 1) return 'عرض نتيجة البطولة';
  final next = gameById(t.games[t.idx + 1]);
  return next == null ? 'اللعبة التالية' : 'التالي: ${next.title}';
}

/// ترتيب البطولة تحت النتيجة
Widget? tourFooter(Session s) {
  if (s is! OnlineSession) return null;
  final room = s.room;
  final t = room.tour;
  if (t == null) return null;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: alpha(const Color(0xFFFFB627), 0.12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: alpha(const Color(0xFFFFB627), 0.5)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('🏆 البطولة: ${t.idx + 1} من ${t.games.length}', style: body(14, weight: FontWeight.w800)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          children: [
            for (final e in t.ranking)
              Text('${room.avatarOfSeat(e.key)} ${room.nameOfSeat(e.key)}: ${e.value}', style: body(13, weight: FontWeight.w700)),
          ],
        ),
      ],
    ),
  );
}

/// أسماء اللاعبين أونلاين (لشاشة النتيجة)
List<String>? namesOf(Session s) {
  if (s is! OnlineSession) return null;
  return [for (var p = 0; p < s.room.seats.length; p++) s.nameOf(p)];
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
          Text('جارٍ الاتصال...', style: body(16, color: C.muted)),
          if (netDebug.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 24, right: 24),
              child: Text(netDebug, textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: body(11, color: C.muted)),
            ),
        ],
      ),
    );
  }
}

/// شريط أعلى اللعبة: إذا انقطع اتصالي، أو انقطع أحد اللاعبين
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
              text = 'انقطع الاتصال... جارٍ إعادة الاتصال';
            } else {
              final gone = [for (var p = 0; p < players; p++) if (p != s.me && !s.isOn(p)) s.nameOf(p)];
              if (gone.isNotEmpty) text = 'انقطع اتصال ${gone.join('، ')}... تستمر اللعبة';
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
