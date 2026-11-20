import 'package:flutter/material.dart';

import '../core/version.dart';
import '../games/registry.dart';
import 'background.dart';
import 'icons.dart';
import 'kit.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  int _players = 2;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();
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
      builder: (_) => _GameSheet(game: g, initialPlayers: _players),
    );
  }

  @override
  Widget build(BuildContext context) {
    // بأول إطار على أندرويد ممكن العرض يكون صفر، والشبكة ما تتحمّل هالشي
    if (MediaQuery.sizeOf(context).width <= 0) return const SizedBox.shrink();
    final list = games.where((g) => g.maxPlayers >= _players).toList();
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: LammaBackground()),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _playersPicker()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.82,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _GameCard(
                        game: list[i],
                        index: i,
                        onTap: () => _open(list[i]),
                      ),
                      childCount: list.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Text(
                      versionLabel,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: body(12, color: alpha(C.muted, 0.7)),
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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, _) => CustomPaint(painter: LogoMarkPainter(t: _spin.value)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Color(0xFFFFFFFF), Color(0xFFC9B8FF)],
                  ).createShader(r),
                  child: Text('لمّة', style: display(52, color: Colors.white)),
                ),
                Text('ألعاب جماعية للأهل والأصدقاء', style: body(15, color: C.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playersPicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: alpha(Colors.white, 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: C.line),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Text('كم لاعب؟', style: body(16, weight: FontWeight.w700, color: C.muted)),
            const SizedBox(width: 8),
            for (final n in [2, 3, 4])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _PlayersChip(
                    n: n,
                    selected: _players == n,
                    onTap: () => setState(() => _players = n),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayersChip extends StatelessWidget {
  const _PlayersChip({required this.n, required this.selected, required this.onTap});
  final int n;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: selected ? alpha(C.accent, 0.3) : Colors.transparent,
          border: Border.all(color: selected ? alpha(C.accent, 0.9) : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$n', style: display(22, color: selected ? Colors.white : C.muted)),
            const SizedBox(width: 6),
            for (var i = 0; i < n; i++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? C.players[i] : alpha(C.players[i], 0.4),
                ),
              ),
          ],
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
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [c0, c1],
            ),
            border: Border.all(color: alpha(Colors.white, 0.16)),
            boxShadow: [
              BoxShadow(color: alpha(c0, 0.28), blurRadius: 22, offset: const Offset(0, 10)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -30,
                left: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: alpha(Colors.white, 0.07),
                  ),
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
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: CustomPaint(painter: game.icon()),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(game.title, style: display(26)),
                    Text(
                      game.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(13, color: alpha(Colors.white, 0.75)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: alpha(Colors.black, 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_alt_rounded, size: 14, color: Colors.white70),
                          const SizedBox(width: 5),
                          Text(game.playersLabel, style: body(12, weight: FontWeight.w700)),
                        ],
                      ),
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

class _GameSheet extends StatefulWidget {
  const _GameSheet({required this.game, required this.initialPlayers});
  final GameInfo game;
  final int initialPlayers;

  @override
  State<_GameSheet> createState() => _GameSheetState();
}

class _GameSheetState extends State<_GameSheet> {
  /// يتذكر آخر وضع اختاروه لكل لعبة (طول ما التطبيق مفتوح)
  static final Map<String, bool> _crazyMemory = {};

  late int _n = widget.initialPlayers.clamp(widget.game.minPlayers, widget.game.maxPlayers);
  late bool _crazy = widget.game.crazyHowTo != null && (_crazyMemory[widget.game.id] ?? false);

  void _start() {
    final g = widget.game;
    final n = _n;
    final crazy = _crazy;
    _crazyMemory[g.id] = crazy;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => g.build(n, crazy),
      transitionsBuilder: (_, anim, __, child) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: 1.06 - 0.06 * t, child: child),
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: C.line),
      ),
      // ينسحب إذا الشاشة صغيرة حتى ما يطلع خطأ (الشرح وخيار الوضع طوّلوه)
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 78,
                  height: 78,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(colors: g.colors),
                  ),
                  child: CustomPaint(painter: g.icon()),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.title, style: display(34)),
                      Text(g.tagline, style: body(15, color: C.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: alpha(Colors.white, 0.04),
                borderRadius: BorderRadius.circular(18),
              ),
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
              const SizedBox(height: 16),
              Text('الوضع', style: body(15, weight: FontWeight.w700, color: C.muted)),
              const SizedBox(height: 8),
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
                      child: _ModeTile(
                        icon: Icons.auto_awesome_rounded,
                        label: 'مجنون',
                        selected: _crazy,
                        color: const Color(0xFFFF8A1F),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (g.maxPlayers > g.minPlayers) ...[
              const SizedBox(height: 16),
              Text('عدد اللاعبين', style: body(15, weight: FontWeight.w700, color: C.muted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var n = g.minPlayers; n <= g.maxPlayers; n++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _PlayersChip(n: n, selected: _n == n, onTap: () => setState(() => _n = n)),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('طريقة اللعب', style: body(15, weight: FontWeight.w700, color: C.muted)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _ModeTile(icon: Icons.phone_android_rounded, label: 'نفس الجهاز', selected: true)),
                const SizedBox(width: 8),
                Expanded(child: _ModeTile(icon: Icons.wifi_rounded, label: 'أونلاين', soon: true)),
              ],
            ),
            const SizedBox(height: 18),
            BigButton(label: 'ابدأ اللعب', icon: Icons.play_arrow_rounded, color: g.colors[0], onTap: _start),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.label,
    this.selected = false,
    this.soon = false,
    this.color = C.accent,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool soon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: soon ? 0.5 : 1,
      child: Container(
        height: 52,
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
            if (soon) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: alpha(Colors.white, 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text('قريباً', style: body(11, weight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
