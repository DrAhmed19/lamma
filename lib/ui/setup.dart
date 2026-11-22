import 'package:flutter/material.dart';

import '../games/registry.dart';
import 'kit.dart';
import 'theme.dart';

/// أسماء المستويات (نفسها لكل الألعاب)
const kLevelNames = ['سهل', 'متوسط', 'صعب'];
const kLevelColors = [Color(0xFF2BD47A), Color(0xFFFFC53D), Color(0xFFFF4D5E)];

/// شاشة البداية "على هذا الجهاز" للألعاب اللي بيها مستويات وكمبيوتر:
/// المستوى (شريط ووجه الكمبيوتر يتغير)، و"منو يلعب؟" (+ شخص / + كمبيوتر)، و"العب"، و"؟".
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.game});
  final GameInfo game;

  @override
  State<SetupScreen> createState() => _SetupState();
}

class _SetupState extends State<SetupScreen> {
  /// آخر اختيار لكل لعبة (طول ما التطبيق مفتوح)
  static final Map<String, (int, List<bool>)> _memory = {};

  late int level;

  /// المقاعد: true = كمبيوتر
  late List<bool> bots;

  GameInfo get g => widget.game;

  @override
  void initState() {
    super.initState();
    final m = _memory[g.id];
    level = m?.$1 ?? 1;
    bots = List.of(m?.$2 ?? [false, true]);
  }

  int get n => bots.length;
  bool get teams => g.teamsAt.contains(n);
  bool get valid => g.fits(n) && bots.contains(false);

  String seatName(int i) {
    if (bots[i]) {
      final k = bots.where((b) => b).length;
      return k == 1 ? 'الكمبيوتر' : 'كمبيوتر ${bots.sublist(0, i + 1).where((b) => b).length}';
    }
    final humans = bots.where((b) => !b).length;
    return humans == 1 ? 'أنت' : C.playerNames[i];
  }

  void _play() {
    if (!valid) return;
    _memory[g.id] = (level, List.of(bots));
    final nav = Navigator.of(context);
    nav.pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => g.play!(level, List.of(bots)),
      transitionsBuilder: (_, anim, __, child) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return Opacity(opacity: t, child: Transform.scale(scale: 1.06 - 0.06 * t, child: child));
      },
    ));
  }

  void _help() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('كيف تلعب؟', textAlign: TextAlign.center, style: display(30, color: L.ink)),
                const SizedBox(height: 10),
                Text(g.howTo, style: body(15, weight: FontWeight.w700, color: L.ink)),
                const SizedBox(height: 12),
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${kLevelNames[i]}: ', style: body(15, weight: FontWeight.w900, color: kLevelColors[i])),
                        TextSpan(text: g.levels![i], style: body(14.5, weight: FontWeight.w700, color: L.ink)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),
                BigButton(label: 'فهمت', onTap: () => Navigator.pop(ctx)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final col = kLevelColors[level];
    return Scaffold(
      backgroundColor: L.sky,
      body: Stack(children: [
        // عالم اللعبة: لون اللعبة من فوق وحافة منحنية
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 290,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(g.colors[0], 0.15), g.colors[0]]),
              borderRadius: BorderRadius.vertical(bottom: Radius.elliptical(MediaQuery.sizeOf(context).width, 70)),
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                    child: Row(
                      children: [
                        _round(Icons.arrow_forward_rounded, () => Navigator.pop(context)),
                        Expanded(child: Text(g.title, textAlign: TextAlign.center, style: display(30, shadows: const [Shadow(color: Color(0x33000000), offset: Offset(0, 3))]))),
                        _round(Icons.question_mark_rounded, _help),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                      child: Column(
                        children: [
                          // وجه الكمبيوتر يتغير ويا المستوى
                          TweenAnimationBuilder<double>(
                            tween: Tween(end: level.toDouble()),
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutBack,
                            builder: (context, v, _) => Container(
                              width: 150,
                              height: 150,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: L.sky2, offset: Offset(0, 7)), BoxShadow(color: Color(0x1F1E325A), blurRadius: 22, offset: Offset(0, 14))]),
                              child: SizedBox(width: 118, height: 118, child: CustomPaint(painter: BotFace(v))),
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(kLevelNames[level], key: ValueKey(level), style: display(34, color: col)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: const [BoxShadow(color: L.sky2, offset: Offset(0, 4))]),
                            child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: col,
                              inactiveTrackColor: const Color(0xFFCBD5E2),
                              thumbColor: col,
                              overlayColor: alpha(col, 0.2),
                              trackHeight: 8,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                              activeTickMarkColor: Colors.transparent,
                              inactiveTickMarkColor: Colors.transparent,
                            ),
                            child: Slider(
                              value: level.toDouble(),
                              min: 0,
                              max: 2,
                              divisions: 2,
                              onChanged: (v) => setState(() => level = v.round()),
                            ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < 3; i++)
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => level = i),
                                    child: Text(kLevelNames[i],
                                        textAlign: i == 0 ? TextAlign.start : (i == 1 ? TextAlign.center : TextAlign.end),
                                        style: body(13, weight: FontWeight.w800, color: i == level ? darken(kLevelColors[i], 0.12) : L.muted)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              key: ValueKey(level),
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: L.sky2, offset: Offset(0, 5))]),
                              child: Text(g.levels![level], textAlign: TextAlign.center, style: body(14.5, weight: FontWeight.w800, color: L.ink)),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text('منو يلعب؟', style: display(26, color: L.ink)),
                          const SizedBox(height: 8),
                          _lineup(),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (n < g.maxPlayers) _addBtn('+ شخص', Icons.person_add_alt_1_rounded, false),
                              if (n < g.maxPlayers) _addBtn('+ كمبيوتر', Icons.smart_toy_rounded, true),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            !g.fits(n)
                                ? 'تُلعب ${g.playersLabel}'
                                : !bots.contains(false)
                                    ? 'أضف شخصًا واحدًا على الأقل'
                                    : 'اضغط على اللاعب لتبديله بين شخص وكمبيوتر',
                            textAlign: TextAlign.center,
                            style: body(13, weight: FontWeight.w800, color: g.fits(n) && bots.contains(false) ? L.muted : const Color(0xFFE5484D)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                    child: Opacity(
                      opacity: valid ? 1 : 0.45,
                      child: SizedBox(
                        width: double.infinity,
                        child: Chunky(
                          color: col,
                          onTap: _play,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                            const SizedBox(width: 6),
                            Text('العب', style: display(32, shadows: const [Shadow(color: Color(0x40000000), offset: Offset(0, 2))])),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _round(IconData icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: L.sky2, offset: Offset(0, 4))]),
          child: Icon(icon, color: L.ink, size: 24),
        ),
      );

  Widget _addBtn(String label, IconData icon, bool bot) {
    return Pressable(
      onTap: () => setState(() => bots.add(bot)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: L.sky2, offset: Offset(0, 4))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: L.ink),
          const SizedBox(width: 6),
          Text(label, style: body(15, weight: FontWeight.w800, color: L.ink)),
        ]),
      ),
    );
  }

  Widget _lineup() {
    if (!teams) {
      return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [for (var i = 0; i < n; i++) _seat(i)]);
    }
    // فريقين: المقاعد الزوجية فريق والفردية فريق (الشركاء متقابلين)
    Widget team(int t) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: alpha(C.players[t], 0.14), borderRadius: BorderRadius.circular(18), border: Border.all(color: alpha(C.players[t], 0.6), width: 2)),
            child: Column(children: [
              Text('الفريق ${t + 1}', style: body(13, weight: FontWeight.w900, color: darken(C.players[t], 0.2))),
              const SizedBox(height: 6),
              for (var i = t; i < n; i += 2) Padding(padding: const EdgeInsets.only(bottom: 6), child: _seat(i, swap: true)),
            ]),
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [team(0), const SizedBox(width: 8), team(1)]);
  }

  Widget _seat(int i, {bool swap = false}) {
    final bot = bots[i];
    final c = C.players[i % C.players.length];
    final canRemove = n > 1;
    return Pressable(
      onTap: () => setState(() => bots[i] = !bots[i]),
      child: Container(
        width: swap ? double.infinity : 150,
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              child: Icon(bot ? Icons.smart_toy_rounded : Icons.person_rounded, size: 19, color: Colors.white),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(seatName(i), maxLines: 1, overflow: TextOverflow.ellipsis, style: body(13, weight: FontWeight.w800, color: L.ink))),
            if (swap)
              GestureDetector(
                onTap: () => setState(() {
                  // ينقل للفريق الثاني: يتبادل ويا اللي بعده
                  final j = (i + 1) % n;
                  final x = bots[i];
                  bots[i] = bots[j];
                  bots[j] = x;
                }),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.swap_horiz_rounded, size: 20, color: L.muted)),
              ),
            if (canRemove)
              GestureDetector(
                onTap: () => setState(() => bots.removeAt(i)),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 18, color: L.muted)),
              ),
          ],
        ),
      ),
    );
  }
}

/// وجه الكمبيوتر: [v] من 0 (سهل: مبتسم أخضر) لـ 2 (صعب: معصّب أحمر بقرون)
class BotFace extends CustomPainter {
  BotFace(this.v);
  final double v;

  Color _col() {
    final x = v.clamp(0.0, 2.0);
    return x <= 1 ? Color.lerp(kLevelColors[0], kLevelColors[1], x)! : Color.lerp(kLevelColors[1], kLevelColors[2], x - 1)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final col = _col();
    final hard = ((v - 1).clamp(0.0, 1.0)).toDouble();
    final easy = ((1 - v).clamp(0.0, 1.0)).toDouble();
    // قرون (الصعب)
    if (hard > 0.05) {
      final horn = Paint()..color = darken(col, 0.25);
      for (final sx in [-1.0, 1.0]) {
        final path = Path()
          ..moveTo(c.dx + sx * s * 0.18, c.dy - s * 0.3)
          ..lineTo(c.dx + sx * s * 0.34, c.dy - s * (0.32 + 0.16 * hard))
          ..lineTo(c.dx + sx * s * 0.3, c.dy - s * 0.18)
          ..close();
        canvas.drawPath(path, horn);
      }
    }
    // هوائي (السهل والمتوسط)
    if (hard < 0.95) {
      final a = Paint()
        ..color = alpha(Colors.white, 1 - hard)
        ..strokeWidth = s * 0.03
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(c.dx, c.dy - s * 0.32), Offset(c.dx, c.dy - s * 0.44), a);
      canvas.drawCircle(Offset(c.dx, c.dy - s * 0.46), s * 0.04, Paint()..color = alpha(col, 1 - hard));
    }
    // الراس
    final head = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 0.74, height: s * 0.64), Radius.circular(s * 0.2));
    canvas.drawRRect(head.shift(Offset(0, s * 0.03)), Paint()..color = alpha(Colors.black, 0.3));
    canvas.drawRRect(head, Paint()..color = col);
    final screen = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 0.6, height: s * 0.48), Radius.circular(s * 0.14));
    canvas.drawRRect(screen, Paint()..color = const Color(0xFF151A2E));
    // العيون
    final eye = Paint()..color = Colors.white;
    for (final sx in [-1.0, 1.0]) {
      final e = Offset(c.dx + sx * s * 0.13, c.dy - s * 0.05);
      canvas.drawCircle(e, s * (0.06 - 0.015 * hard), eye);
      // الحواجب: معصّبة بالصعب
      final brow = Paint()
        ..color = Colors.white
        ..strokeWidth = s * 0.03
        ..strokeCap = StrokeCap.round;
      final tilt = (hard * 0.06 - easy * 0.02) * s;
      canvas.drawLine(Offset(e.dx - s * 0.06, e.dy - s * 0.1 - sx * tilt * -1), Offset(e.dx + s * 0.06, e.dy - s * 0.1 + sx * tilt * -1), brow);
    }
    // الحلگ: ابتسامة ← مستقيم ← ابتسامة شريرة بأسنان
    final mouth = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round;
    final my = c.dy + s * 0.12;
    final curve = (easy * 0.07 + hard * 0.05) * s;
    final path = Path()
      ..moveTo(c.dx - s * 0.13, my)
      ..quadraticBezierTo(c.dx, my + curve, c.dx + s * 0.13, my);
    canvas.drawPath(path, mouth);
    if (hard > 0.4) {
      final tooth = Paint()..color = Colors.white;
      for (final sx in [-0.06, 0.06]) {
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + sx * s - s * 0.02, my + curve * 0.4)
            ..lineTo(c.dx + sx * s + s * 0.02, my + curve * 0.4)
            ..lineTo(c.dx + sx * s, my + curve * 0.4 + s * 0.045 * hard)
            ..close(),
          tooth,
        );
      }
    }
    // خدود (السهل)
    if (easy > 0.05) {
      for (final sx in [-1.0, 1.0]) {
        canvas.drawCircle(Offset(c.dx + sx * s * 0.22, c.dy + s * 0.08), s * 0.04, Paint()..color = alpha(const Color(0xFFFF8FA3), 0.6 * easy));
      }
    }
  }

  @override
  bool shouldRepaint(BotFace old) => old.v != v;
}
