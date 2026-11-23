import 'package:flutter/material.dart';

import '../games/registry.dart';
import 'art.dart';
import 'kit.dart';
import 'theme.dart';

/// أسماء المستويات (نفسها لكل الألعاب)
const kLevelNames = ['سهل', 'متوسط', 'صعب'];
const kLevelColors = [Color(0xFF2BD47A), Color(0xFFFFC53D), Color(0xFFFF4D5E)];

/// خيار جاهز بـ«شلون تلعبون؟»: عنوان، سطر توضيح، والمقاعد (true = كمبيوتر)
class _Opt {
  const _Opt(this.title, this.sub, this.bots);
  final String title, sub;
  final List<bool> bots;
}

/// شاشة البداية «على هذا الجهاز» للألعاب اللي بيها مستويات وكمبيوتر، حسب النموذج:
/// سؤال واحد بكل شاشة: «كم شخص على هذا الهاتف؟» ← «ضد منو تلعب؟ / شلون تلعبون؟» (خيارات جاهزة)
/// ← المستوى (وجه الكمبيوتر والشريط) و«العب». إذا الجواب واحد، الخطوة تنعبر وحدها.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.game});
  final GameInfo game;

  @override
  State<SetupScreen> createState() => _SetupState();
}

class _SetupState extends State<SetupScreen> {
  /// آخر مستوى لكل لعبة (طول ما التطبيق مفتوح)
  static final Map<String, int> _memory = {};

  late int level;

  /// 0 = كم شخص، 1 = شلون تلعبون، 2 = المستوى
  int step = 0;
  int humans = 1;
  List<_Opt> opts = const [];

  /// المقاعد: true = كمبيوتر
  List<bool> bots = const [false, true];

  GameInfo get g => widget.game;

  @override
  void initState() {
    super.initState();
    level = _memory[g.id] ?? 1;
  }

  int get maxHumans => g.maxPlayers < 4 ? g.maxPlayers : 4;
  bool get fourTeams => g.teamsAt.contains(4) && g.fits(4);

  /// الخيارات الجاهزة حسب عدد الأشخاص (مثل النموذج)
  List<_Opt> _options(int h) {
    final o = <_Opt>[];
    if (h == 1) {
      if (g.fits(2)) o.add(const _Opt('ضد الكمبيوتر', 'وجهًا لوجه', [false, true]));
      if (fourTeams) {
        o.add(const _Opt('أنا وكمبيوتر ضد كمبيوترين', 'أربعة، فريقان', [false, true, true, true]));
      } else if (g.maxPlayers > 2 && g.fits(g.maxPlayers)) {
        o.add(_Opt('ضد كمبيوترات أكثر', 'حتى ${g.maxPlayers} لاعبين', [false, for (var i = 1; i < g.maxPlayers; i++) true]));
      }
    } else {
      if (g.fits(h)) o.add(_Opt('بينكم فقط', h == 2 ? 'واحد ضد واحد' : '$h لاعبين', List.filled(h, false)));
      if (h == 2 && fourTeams) {
        // الفرق بالمقاعد: 0 و2 فريق، 1 و3 فريق
        o.add(const _Opt('أنتما فريق', 'ضد كمبيوترين', [false, true, false, true]));
        o.add(const _Opt('كل واحد معه كمبيوتر', 'اثنان ضد اثنين', [false, false, true, true]));
      } else if (h == 3 && fourTeams) {
        o.add(const _Opt('مع كمبيوتر واحد', 'أربعة، فريقان', [false, false, false, true]));
      } else if (h < g.maxPlayers && g.fits(h + 1)) {
        o.add(_Opt('نضيف كمبيوتر', '${h + 1} لاعبين', [...List.filled(h, false), true]));
      }
    }
    return o;
  }

  void _pickHumans(int h) {
    final o = _options(h);
    if (o.isEmpty) return;
    setState(() {
      humans = h;
      opts = o;
      if (o.length == 1) {
        bots = o.first.bots;
        step = 2;
      } else {
        step = 1;
      }
    });
  }

  void _pickOpt(_Opt o) => setState(() {
        bots = o.bots;
        step = 2;
      });

  void _back() {
    if (step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => step = step == 2 && opts.length > 1 ? 1 : 0);
    }
  }

  void _play() {
    _memory[g.id] = level;
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
                ChunkyButton(label: 'فهمت', onTap: () => Navigator.pop(ctx)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _question => switch (step) {
        0 => 'كم شخص على هذا الهاتف؟',
        1 => humans == 1 ? 'ضد من تلعب؟' : 'كيف تلعبون؟',
        _ => g.title,
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: L.sky,
        body: Stack(children: [
          // عالم اللعبة: لون اللعبة من فوق وحافة منحنية
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 290,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(bottom: Radius.elliptical(MediaQuery.sizeOf(context).width, 70)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [lighten(g.colors[0], 0.15), g.colors[0]]),
                ),
                // نقشة: صورة اللعبة مكررة بشفافية ومايلة (مثل النموذج)
                child: RepaintBoundary(child: GamePattern(id: g.id, fallback: g.icon)),
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
                          _round(Icons.arrow_forward_rounded, _back),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(_question, textAlign: TextAlign.center, style: display(28, shadows: const [Shadow(color: Color(0x33000000), offset: Offset(0, 3))])),
                            ),
                          ),
                          _round(Icons.question_mark_rounded, _help),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // شريط الخطوات (3)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < 3; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 24,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(color: alpha(Colors.white, i <= step ? 1 : 0.45), borderRadius: BorderRadius.circular(4)),
                        ),
                    ]),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: KeyedSubtree(
                          key: ValueKey('$step-$humans'),
                          child: step == 0 ? _humansStep() : (step == 1 ? _optsStep() : _levelStep()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// الخطوة 1: أزرار كبيرة 1..4 بألوان المقاعد ويا أشخاص صغار
  Widget _humansStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 40, 18, 16),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.15,
            children: [
              for (var h = 1; h <= maxHumans; h++)
                if (_options(h).isNotEmpty)
                  Chunky(
                    color: C.players[h - 1],
                    radius: 26,
                    onTap: () => _pickHumans(h),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$h', style: display(54, shadows: const [Shadow(color: Color(0x33000000), offset: Offset(0, 3))])),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (var k = 0; k < h; k++) const Icon(Icons.person_rounded, color: Colors.white, size: 24),
                        ]),
                      ],
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          Text('الكمبيوتر يكمّل الباقي إذا أردت', textAlign: TextAlign.center, style: body(14, weight: FontWeight.w800, color: L.muted)),
        ],
      ),
    );
  }

  /// الخطوة 2: خيارات جاهزة عريضة ويا صور مصغّرة (أشخاص + كمبيوترات)
  Widget _optsStep() {
    const cols = [Color(0xFF3DB56E), Color(0xFF2E9BF0), Color(0xFF9B5DE5)];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 40, 18, 16),
      child: Column(
        children: [
          for (var i = 0; i < opts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Chunky(
                color: cols[i % cols.length],
                onTap: () => _pickOpt(opts[i]),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(opts[i].title, style: display(22, shadows: const [Shadow(color: Color(0x33000000), offset: Offset(0, 2))])),
                        Text(opts[i].sub, style: body(13, weight: FontWeight.w800, color: alpha(Colors.white, 0.92))),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    _preview(opts[i].bots),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// صور مصغّرة: الأشخاص بألوان مقاعدهم، و«+» والكمبيوترات
  Widget _preview(List<bool> b) {
    Widget dot(Color c, IconData i) => Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: alpha(Colors.white, 0.8), width: 2)),
          child: Icon(i, size: 17, color: Colors.white),
        );
    final hs = [for (var i = 0; i < b.length; i++) if (!b[i]) dot(C.players[i], Icons.person_rounded)];
    final bs = [for (var i = 0; i < b.length; i++) if (b[i]) dot(const Color(0xFF8FA0BD), Icons.smart_toy_rounded)];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ...hs,
      if (bs.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Text('+', style: display(18))),
      ...bs,
    ]);
  }

  /// الخطوة 3: المستوى (وجه الكمبيوتر يتغير) و«العب»
  Widget _levelStep() {
    final col = kLevelColors[level];
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
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
                // مكان ثابت للوصف: تغيير المستوى ما يحرّك الأزرار
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 86),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: L.sky2, offset: Offset(0, 5))]),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(g.levels![level], key: ValueKey(level), textAlign: TextAlign.center, style: body(14.5, weight: FontWeight.w800, color: L.ink)),
                  ),
                ),
                const SizedBox(height: 12),
                // تذكير بالتشكيلة المختارة
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: alpha(L.ink, 0.75), borderRadius: BorderRadius.circular(20)),
                  child: _preview(bots),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
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
      ],
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
