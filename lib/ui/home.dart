import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/profile.dart';
import '../core/updater.dart';
import '../core/version.dart';
import '../games/registry.dart';
import '../net/lan.dart';
import '../net/room.dart';
import 'background.dart';
import 'flow.dart';
import 'icons.dart';
import 'invite.dart';
import 'kit.dart';
import 'profile_ui.dart';
import 'setup.dart';
import 'art.dart';
import 'theme.dart';
import 'update.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
    Updater.I.check();
    // رابط دعوة بالويب (/j/CODE يتحول لـ ?room=CODE): يدخل الغرفة مباشرة
    final q = Uri.base.queryParameters;
    final code = q['room'];
    if (code != null && code.length == 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openInvite(context, code, gone: q['gone'] == '1');
      });
    }
    // أندرويد: رابط /j/CODE فتح التطبيق (أول تشغيل أو والتطبيق مفتوح)
    if (!kIsWeb) {
      _links = AppLinks().uriLinkStream.listen(_onLink, onError: (_) {});
    }
  }

  StreamSubscription<Uri>? _links;
  String? _lastLink;
  DateTime _lastLinkAt = DateTime(0);

  void _onLink(Uri uri) {
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty || seg.first != 'j') return;
    // نفس الرابط مرتين ورا بعض (أول تشغيل) = مرة وحدة
    final now = DateTime.now();
    if (uri.toString() == _lastLink && now.difference(_lastLinkAt).inSeconds < 5) return;
    _lastLink = uri.toString();
    _lastLinkAt = now;
    if (seg.length < 2) return; // /j/ بدون غرفة: يكفي إن التطبيق انفتح
    // فتح رابط غرفته اللي هو بيها هسة: يبقى بمكانه
    if (seg[1].toUpperCase() == RoomConn.activeCode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // إذا كان بغرفة ثانية أو لعبة: نرجع للرئيسية أول
      Navigator.of(context).popUntil((r) => r.isFirst);
      openInvite(context, seg[1]);
    });
  }

  @override
  void dispose() {
    _links?.cancel();
    _spin.dispose();
    super.dispose();
  }

  void _open(GameInfo g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GameSheet(game: g),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width <= 0) return const SizedBox.shrink();
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: LightBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _header()),
                    const SliverToBoxAdapter(child: UpdateBanner()),
                    const SliverToBoxAdapter(child: GetAppBanner()),
                    SliverToBoxAdapter(child: _duo()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Text('كل الألعاب', style: display(23, color: L.ink)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 135,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _GameCard(game: games[i], index: i, onTap: () => _open(games[i])),
                          childCount: games.length,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Pressable(
                          onTap: Updater.I.supported ? () => showUpdateSheet(context) : null,
                          child: Text(
                            Updater.I.supported ? '$versionLabel · التحقق من التحديثات' : versionLabel,
                            textAlign: TextAlign.center,
                            style: body(12, color: alpha(C.muted, 0.7)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _spin,
                builder: (context, _) => CustomPaint(painter: LogoMarkPainter(t: _spin.value)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('لمّة', style: display(48, color: L.ink, shadows: const [Shadow(color: Colors.white, offset: Offset(0, 3))])),
                Text('ألعاب جماعية للعائلة والأصدقاء', style: body(14, color: L.muted, weight: FontWeight.w800)),
              ],
            ),
          ),
          // الملف الشخصي
          ListenableBuilder(
            listenable: Profile.I,
            builder: (context, _) => Pressable(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(color: Color(0x22000000), offset: Offset(0, 3))],
                    ),
                    child: Avatar(Profile.I.avatar, size: 34),
                  ),
                  const SizedBox(height: 2),
                  Text(Profile.I.hasName ? Profile.I.name : 'ملفي', style: body(12, weight: FontWeight.w800, color: L.ink)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقتان كبيرتان: الانضمام إلى صديق، وادعُ صديق (واتساب)
  Widget _duo() {
    final canJoin = onlineAvailable || lanHostSupported;
    final canInvite = lanOrigin == null;
    if (!canJoin && !canInvite) return const SizedBox.shrink();
    Widget tile(Color c, IconData icon, String title, String sub, VoidCallback tap) => Expanded(
          child: Chunky(
            color: c,
            onTap: tap,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: alpha(Colors.white, 0.25), borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(title, maxLines: 1, style: display(21))),
                  Text(sub, maxLines: 2, style: body(12, weight: FontWeight.w800, color: alpha(Colors.white, 0.9))),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canJoin) tile(const Color(0xFF3DB56E), Icons.group_add_rounded, 'الانضمام إلى صديق', 'هل أرسل لك صديقك رمزًا؟', () => showJoinSheet(context)),
          if (canJoin && canInvite) const SizedBox(width: 10),
          if (canInvite) tile(kWhatsApp, Icons.chat_rounded, 'ادعُ صديقًا', 'أرسل رابط لمّة بواتساب', () => sendWhatsApp(appInviteText)),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.index, required this.onTap});
  final GameInfo game;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c1 = game.colors[1];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
      ),
      child: Pressable(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(color: darken(c1, 0.25), offset: const Offset(0, 6)),
                          const BoxShadow(color: Color(0x1E1E325A), blurRadius: 18, offset: Offset(0, 12))
                        ],
                      ),
                      child: GameArt(game.id, fallback: game.icon, radius: 28),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(game.title, maxLines: 1, style: display(18, color: L.ink))),
            FittedBox(fit: BoxFit.scaleDown, child: Text(game.playersLabel, maxLines: 1, style: body(11.5, weight: FontWeight.w800, color: L.muted))),
          ],
        ),
      ),
    );
  }
}

/// نافذة اللعبة: الشرح، ثم ثلاث طرق للعب بأزرار كبيرة وواضحة
class _GameSheet extends StatefulWidget {
  const _GameSheet({required this.game});
  final GameInfo game;

  @override
  State<_GameSheet> createState() => _GameSheetState();
}

class _GameSheetState extends State<_GameSheet> {
  static final Map<String, bool> _crazyMemory = {};
  late bool _crazy = widget.game.crazyHowTo != null && (_crazyMemory[widget.game.id] ?? false);

  /// على هذا الجهاز: إذا اللعبة لأكثر من لاعبين نسأل كم لاعب
  Future<void> _here() async {
    final g = widget.game;
    // ألعاب المستويات: شاشة البداية (المستوى + منو يلعب ويا الكمبيوتر)
    if (g.play != null) {
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => SetupScreen(game: g)));
      return;
    }
    var n = g.minPlayers;
    if (g.maxPlayers > g.minPlayers) {
      final pick = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('كم عدد اللاعبين؟', style: display(28, color: L.ink)),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final k in g.allowedCounts)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Pressable(
                          onTap: () => Navigator.pop(ctx, k),
                          child: Container(
                            height: 90,
                            decoration: BoxDecoration(
                              color: L.sky,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [BoxShadow(color: L.sky2, offset: Offset(0, 4))],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('$k', style: display(38, color: L.ink)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < k; i++)
                                      Container(
                                        width: 9,
                                        height: 9,
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        decoration: BoxDecoration(shape: BoxShape.circle, color: C.players[i]),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      if (pick == null) return;
      n = pick;
    }
    if (!mounted) return;
    _crazyMemory[g.id] = _crazy;
    final crazy = _crazy;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => g.build(n, crazy),
      transitionsBuilder: (_, anim, __, child) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return Opacity(opacity: t, child: Transform.scale(scale: 1.06 - 0.06 * t, child: child));
      },
    ));
  }

  void _friends() {
    final nav = Navigator.of(context);
    final ctx = nav.context;
    nav.pop();
    createFriendsRoom(ctx, game: widget.game);
  }

  void _others() {
    final nav = Navigator.of(context);
    final ctx = nav.context;
    nav.pop();
    quickMatch(ctx, widget.game);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final canFriends = g.online != null && (onlineAvailable || lanHostSupported);
    final canOthers = g.online != null && g.quick && onlineAvailable && lanOrigin == null;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [BoxShadow(color: Color(0x331E325A), blurRadius: 30, offset: Offset(0, 10))]),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(width: 42, height: 5, decoration: BoxDecoration(color: L.sky2, borderRadius: BorderRadius.circular(3))),
                ),
                const SizedBox(height: 14),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(g.colors[0], 0.12), g.colors[0]]),
                  ),
                  child: Stack(children: [
                    Positioned.fill(child: RepaintBoundary(child: GamePattern(id: g.id, fallback: g.icon, cell: 52))),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [BoxShadow(color: Color(0x33000000), offset: Offset(0, 4))],
                            ),
                            child: GameArt(g.id, fallback: g.icon, size: 78, radius: 21),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g.title, style: display(32, shadows: const [Shadow(color: Color(0x33000000), offset: Offset(0, 3))])),
                                Text(g.tagline, style: body(14, weight: FontWeight.w800, color: alpha(Colors.white, 0.92))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: L.sky, borderRadius: BorderRadius.circular(18)),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _crazy ? g.crazyHowTo! : g.howTo,
                      key: ValueKey(_crazy),
                      style: body(15.5, weight: FontWeight.w700, color: L.ink),
                    ),
                  ),
                ),
                if (g.crazyHowTo != null && g.levels == null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Pressable(
                          onTap: () => setState(() => _crazy = false),
                          child: _ModeTile(icon: Icons.spa_rounded, label: g.modeLabels?[0] ?? 'عادي', selected: !_crazy),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Pressable(
                          onTap: () => setState(() => _crazy = true),
                          child: _ModeTile(
                              icon: g.modeLabels != null ? Icons.flag_rounded : Icons.auto_awesome_rounded,
                              label: g.modeLabels?[1] ?? 'مجنون',
                              selected: _crazy,
                              color: const Color(0xFFFF8A1F)),
                        ),
                      ),
                    ],
                  ),
                ],
                if (g.local) ...[
                  const SizedBox(height: 18),
                  _Choice(
                    icon: Icons.phone_android_rounded,
                    title: 'على هذا الجهاز',
                    subtitle: g.play != null ? 'وحدك ضد الكمبيوتر أو مع من حولك' : 'الجميع يلعبون على هذا الهاتف معًا',
                    color: const Color(0xFF2E9BF0),
                    primary: true,
                    onTap: _here,
                  ),
                ],
                if (canFriends) ...[
                  SizedBox(height: g.local ? 10 : 18),
                  _Choice(
                    icon: Icons.people_rounded,
                    title: 'مع أصدقائي',
                    subtitle: g.local ? 'كل شخص على هاتفه، وأرسل إليهم الدعوة' : 'كل شخص على هاتفه (${g.playersLabel})',
                    color: const Color(0xFF3DB56E),
                    primary: !g.local,
                    onTap: _friends,
                  ),
                ],
                if (!g.local && !canFriends) ...[
                  const SizedBox(height: 18),
                  Text('تحتاج هذه اللعبة إلى أن يلعب كل شخص على هاتفه.', textAlign: TextAlign.center, style: body(14, weight: FontWeight.w800, color: L.muted)),
                ],
                if (canOthers) ...[
                  const SizedBox(height: 10),
                  _Choice(
                    icon: Icons.public_rounded,
                    title: 'مع لاعبين آخرين',
                    subtitle: 'العب مع أشخاص آخرين عبر الإنترنت',
                    color: const Color(0xFF9B5DE5),
                    onTap: _others,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// زر كبير بأيقونة وعنوان وشرح سطر واحد
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Chunky(
      color: color,
      onTap: onTap,
      radius: 22,
      edge: 5,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: alpha(Colors.white, 0.22), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: Colors.white, size: 27),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: display(23)),
                Text(subtitle, style: body(12.5, weight: FontWeight.w800, color: alpha(Colors.white, 0.92))),
              ],
            ),
          ),
          const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 16),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.icon, required this.label, this.selected = false, this.color = C.accent});
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: selected ? alpha(color, 0.2) : L.sky,
        border: Border.all(color: selected ? color : L.sky2, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: L.ink),
          const SizedBox(width: 8),
          Text(label, style: body(15, weight: FontWeight.w800, color: L.ink)),
        ],
      ),
    );
  }
}
