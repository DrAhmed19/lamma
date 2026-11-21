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
import 'kit.dart';
import 'profile_ui.dart';
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
    // رابط دعوة بالويب: ?room=ABCD يفتح الانضمام والرمز مكتوب
    final code = Uri.base.queryParameters['room'];
    if (code != null && code.length == 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showJoinSheet(context, code: code);
      });
    }
  }

  @override
  void dispose() {
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
          const Positioned.fill(child: LammaBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _header()),
                    const SliverToBoxAdapter(child: UpdateBanner()),
                    SliverToBoxAdapter(child: _joinCard()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Text('اختر لعبة', style: body(17, weight: FontWeight.w800, color: C.muted)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.86,
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
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFC9B8FF)]).createShader(r),
                  child: Text('لمّة', style: display(48, color: Colors.white)),
                ),
                Text('ألعاب جماعية للعائلة والأصدقاء', style: body(14, color: C.muted)),
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
                      color: alpha(C.accent, 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: alpha(C.accent, 0.7), width: 2),
                    ),
                    child: Text(Profile.I.avatar, style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(height: 2),
                  Text(Profile.I.hasName ? Profile.I.name : 'ملفي', style: body(12, weight: FontWeight.w700, color: C.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقة واحدة واضحة: أرسل لك صديقك رمزًا؟
  Widget _joinCard() {
    if (!onlineAvailable && !lanHostSupported) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Pressable(
        onTap: () => showJoinSheet(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(colors: [Color(0xFF2A1F6B), Color(0xFF1A2150)]),
            border: Border.all(color: alpha(C.accent, 0.6)),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: alpha(C.accent, 0.3), shape: BoxShape.circle),
                child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الانضمام إلى صديق', style: body(19, weight: FontWeight.w800)),
                    Text('هل أرسل إليك صديقك رمزًا؟ اضغط هنا', style: body(14, color: alpha(Colors.white, 0.75))),
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
            ],
          ),
        ),
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
    final c0 = game.colors[0], c1 = game.colors[1];
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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [c0, c1]),
            border: Border.all(color: alpha(Colors.white, 0.16)),
            boxShadow: [BoxShadow(color: alpha(c0, 0.22), blurRadius: 8, offset: const Offset(0, 6))],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -30,
                left: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: alpha(Colors.white, 0.07)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Padding(padding: const EdgeInsets.all(6), child: CustomPaint(painter: game.icon())),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(game.title, maxLines: 1, style: display(24)),
                    ),
                    Text(game.tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: body(13, color: alpha(Colors.white, 0.75))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.people_alt_rounded, size: 14, color: Colors.white70),
                        const SizedBox(width: 5),
                        Text(game.playersLabel, style: body(12, weight: FontWeight.w700, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    var n = g.minPlayers;
    if (g.maxPlayers > g.minPlayers) {
      final pick = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: C.line)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('كم عدد اللاعبين؟', style: display(28)),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var k = g.minPlayers; k <= g.maxPlayers; k++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Pressable(
                          onTap: () => Navigator.pop(ctx, k),
                          child: Container(
                            height: 90,
                            decoration: BoxDecoration(
                              color: alpha(C.accent, 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: alpha(C.accent, 0.6)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('$k', style: display(38)),
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
    final canOthers = g.online != null && onlineAvailable && lanOrigin == null;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(30), border: Border.all(color: C.line)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(width: 42, height: 5, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(3))),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: LinearGradient(colors: g.colors)),
                      child: CustomPaint(painter: g.icon()),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.title, style: display(32)),
                          Text(g.tagline, style: body(15, color: C.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: alpha(Colors.white, 0.04), borderRadius: BorderRadius.circular(18)),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _crazy ? g.crazyHowTo! : g.howTo,
                      key: ValueKey(_crazy),
                      style: body(15.5, color: alpha(Colors.white, 0.85)),
                    ),
                  ),
                ),
                if (g.crazyHowTo != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Pressable(
                          onTap: () => setState(() => _crazy = false),
                          child: _ModeTile(icon: Icons.spa_rounded, label: 'عادي', selected: !_crazy),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Pressable(
                          onTap: () => setState(() => _crazy = true),
                          child: _ModeTile(icon: Icons.auto_awesome_rounded, label: 'مجنون', selected: _crazy, color: const Color(0xFFFF8A1F)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                _Choice(
                  icon: Icons.phone_android_rounded,
                  title: 'على هذا الجهاز',
                  subtitle: 'الجميع يلعبون على هذا الهاتف معًا',
                  color: g.colors[0],
                  primary: true,
                  onTap: _here,
                ),
                if (canFriends) ...[
                  const SizedBox(height: 10),
                  _Choice(
                    icon: Icons.people_rounded,
                    title: 'مع أصدقائي',
                    subtitle: 'كل شخص على هاتفه، وأرسل إليهم الدعوة',
                    color: const Color(0xFF16B46A),
                    onTap: _friends,
                  ),
                ],
                if (canOthers) ...[
                  const SizedBox(height: 10),
                  _Choice(
                    icon: Icons.public_rounded,
                    title: 'مع لاعبين آخرين',
                    subtitle: 'العب مع أشخاص آخرين عبر الإنترنت',
                    color: const Color(0xFF3D8BFF),
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
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: primary ? LinearGradient(colors: [lighten(color, 0.08), darken(color, 0.15)]) : null,
          color: primary ? null : alpha(color, 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: alpha(primary ? Colors.white : color, primary ? 0.25 : 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: alpha(Colors.white, primary ? 0.2 : 0.08), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: body(18, weight: FontWeight.w800)),
                  Text(subtitle, style: body(13, color: alpha(Colors.white, 0.8))),
                ],
              ),
            ),
            const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 16),
          ],
        ),
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
        color: selected ? alpha(color, 0.22) : alpha(Colors.white, 0.04),
        border: Border.all(color: selected ? alpha(color, 0.8) : C.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: body(15, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}
