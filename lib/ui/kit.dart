import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fx.dart';
import '../core/perf.dart';
import '../net/room.dart';
import 'icons.dart';
import 'react.dart';
import 'theme.dart';

/// زر يصغر شوية عند الضغط.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.95});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              Fx.tap();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// زر رئيسي عريض
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = C.accent,
    this.icon,
    this.filled = true,
  });
  final String label;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: filled
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [lighten(color, 0.12), darken(color, 0.12)],
                )
              : null,
          color: filled ? null : alpha(Colors.white, 0.06),
          border: Border.all(
            color: filled ? alpha(Colors.white, 0.18) : C.line,
          ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: alpha(color, 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
            ],
            Text(label, style: body(18, weight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// زر دائري زجاجي صغير (الإيقاف مثلاً)
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap, this.size = 44});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.88,
      // بدون تمويه الخلفية: هذا الزر فوق اللعبة طول الوقت، والتمويه يقطّع بالمتصفح
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: alpha(const Color(0xFF0B1022), 0.62),
          border: Border.all(color: alpha(Colors.white, 0.22)),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

/// غلاف كل لعبة: خلفية + زر إيقاف + زر رجوع الجهاز يفتح الإيقاف.
class GameScaffold extends StatelessWidget {
  const GameScaffold({super.key, required this.child, required this.onPause, this.room});
  final Widget child;
  final VoidCallback onPause;

  /// أونلاين: زر التفاعلات السريعة، وتظهر تفاعلات الباقين فوق اللعبة
  final RoomConn? room;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) onPause();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        body: Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlassIconButton(
                      icon: Icons.pause_rounded,
                      onTap: onPause,
                      size: 42,
                    ),
                    if (room != null) ...[
                      const SizedBox(height: 10),
                      ReactButton(room: room!),
                    ],
                  ],
                ),
              ),
            ),
            if (room != null) Positioned.fill(child: IgnorePointer(child: ReactLayer(room: room!))),
            // عدّاد الأداء (مؤقت للتشخيص)
            Positioned(
              left: 8,
              bottom: 6,
              child: IgnorePointer(
                child: ValueListenableBuilder<String>(
                  valueListenable: perfText,
                  builder: (_, t, __) => Text(t, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: Color(0x99FFFFFF))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum PauseAction { resume, restart, exit }

Future<PauseAction> showPauseMenu(BuildContext context) async {
  final r = await showGeneralDialog<PauseAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'pause',
    barrierColor: alpha(Colors.black, 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a1, a2) => const _PauseMenu(),
    transitionBuilder: (ctx, anim, a2, child) {
      final t = Curves.easeOutBack.transform(anim.value);
      return Opacity(
        opacity: anim.value,
        child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      );
    },
  );
  return r ?? PauseAction.resume;
}

class _PauseMenu extends StatelessWidget {
  const _PauseMenu();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: C.line),
            boxShadow: [
              BoxShadow(color: alpha(Colors.black, 0.5), blurRadius: 40),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إيقاف مؤقت', textAlign: TextAlign.center, style: display(38)),
              const SizedBox(height: 18),
              BigButton(
                label: 'متابعة',
                icon: Icons.play_arrow_rounded,
                onTap: () => Navigator.pop(context, PauseAction.resume),
              ),
              const SizedBox(height: 10),
              BigButton(
                label: 'إعادة اللعبة',
                icon: Icons.replay_rounded,
                filled: false,
                onTap: () => Navigator.pop(context, PauseAction.restart),
              ),
              const SizedBox(height: 10),
              BigButton(
                label: 'الخروج',
                icon: Icons.grid_view_rounded,
                filled: false,
                onTap: () => Navigator.pop(context, PauseAction.exit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عد تنازلي 3-2-1-يلا. dual = نسخة مقلوبة للاعب المقابل.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.onDone, this.dual = false, this.paused = false});
  final VoidCallback onDone;
  final bool dual;

  /// يوقف العد ويا الإيقاف المؤقت للعبة.
  final bool paused;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  int _lastStep = -1;
  static const _labels = ['3', '2', '1', 'انطلق!'];

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
      ..addListener(_onTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
    if (widget.paused) _c.stop();
  }

  @override
  void didUpdateWidget(covariant Countdown old) {
    super.didUpdateWidget(old);
    if (widget.paused != old.paused) {
      if (widget.paused) {
        _c.stop();
      } else if (!_c.isCompleted) {
        _c.forward();
      }
    }
  }

  void _onTick() {
    final step = (_c.value * 4).floor().clamp(0, 3);
    if (step != _lastStep) {
      _lastStep = step;
      if (step == 3) {
        Fx.mid();
      } else {
        Fx.tap();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * 4;
          final i = t.floor().clamp(0, 3);
          final f = (t - i).clamp(0.0, 1.0);
          final scale = 0.4 + 0.8 * Curves.easeOutBack.transform(math.min(1.0, f * 2.2));
          final op = i == 3 ? (1 - f).clamp(0.0, 1.0) : (f < 0.8 ? 1.0 : (1 - (f - 0.8) / 0.2));
          final color = i == 3 ? C.go : Colors.white;
          final one = Opacity(
            opacity: op.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: Text(
                _labels[i],
                style: display(i == 3 ? 92.0 : 120.0, color: color, shadows: [
                  // حافة غامقة حتى يبين حتى على الخلفيات الفاتحة
                  Shadow(color: alpha(const Color(0xFF0B1230), 0.55), blurRadius: 3, offset: const Offset(0, 4)),
                  Shadow(color: alpha(color, 0.6), blurRadius: 30),
                ]),
              ),
            ),
          );
          if (!widget.dual) return Center(child: one);
          return Column(
            children: [
              Expanded(child: Center(child: RotatedBox(quarterTurns: 2, child: one))),
              Expanded(child: Center(child: one)),
            ],
          );
        },
      ),
    );
  }
}

/// شاشة النتيجة
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.winner,
    required this.scores,
    required this.onAgain,
    this.dual = false,
    this.subtitle,
    this.seats,
    this.menuLabel,
    this.onMenu,
    this.againLabel,
    this.footer,
    this.names,
  });

  /// نص زر الإعادة (بالبطولة: "اللعبة التالية")
  final String? againLabel;

  /// شي إضافي تحت النتيجة (ترتيب البطولة مثلاً)
  final Widget? footer;

  /// أسماء اللاعبين (أونلاين). إذا null نستخدم أسماء الألوان.
  final List<String>? names;

  /// الزر الثاني (افتراضياً يرجع للقائمة). أونلاين: يرجع للغرفة.
  final String? menuLabel;
  final VoidCallback? onMenu;

  /// رقم لون كل لاعب (إذا اللعبة تستخدم ألوان غير الترتيب الافتراضي)
  final List<int>? seats;

  int _seat(int i) => seats == null ? i : seats![i];

  /// -1 = تعادل
  final int winner;
  final List<int> scores;
  final VoidCallback onAgain;
  final bool dual;
  final String? subtitle;

  String get _title => winner < 0 ? 'تعادل!' : 'فاز ${names != null && winner < names!.length ? names![winner] : C.playerNames[_seat(winner)]}!';
  Color get _color => winner < 0 ? Colors.white : C.players[_seat(winner)];

  Widget _banner() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (winner >= 0)
          SizedBox(
            width: 70,
            height: 54,
            child: CustomPaint(painter: CrownPainter(_color)),
          ),
        Text(
          _title,
          textAlign: TextAlign.center,
          style: display(46, color: _color, shadows: [
            Shadow(color: alpha(_color, 0.6), blurRadius: 24),
          ]),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: body(16, color: C.muted)),
          ),
      ],
    );
  }

  Widget _scores() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < scores.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: alpha(C.players[_seat(i)], i == winner ? 0.28 : 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: alpha(C.players[_seat(i)], i == winner ? 0.9 : 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: C.players[_seat(i)], shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('${scores[i]}', style: display(24)),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _banner(),
        const SizedBox(height: 16),
        _scores(),
        if (footer != null) ...[
          const SizedBox(height: 14),
          footer!,
        ],
        const SizedBox(height: 22),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BigButton(label: againLabel ?? 'العب مرة أخرى', icon: Icons.replay_rounded, onTap: onAgain, color: winner >= 0 ? _color : C.accent),
            const SizedBox(width: 10),
            BigButton(
              label: menuLabel ?? 'الرئيسية',
              filled: false,
              onTap: onMenu ?? () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      ),
      child: Stack(
        children: [
          // تعتيم بدون تمويه (التمويه فوق لعبة شغالة غالي بالمتصفح)
          Positioned.fill(child: Container(color: alpha(const Color(0xFF05070F), 0.72))),
          if (dual)
            Column(
              children: [
                Expanded(child: Center(child: RotatedBox(quarterTurns: 2, child: _banner()))),
                Expanded(child: Center(child: panel)),
              ],
            )
          else
            Center(child: panel),
        ],
      ),
    );
  }
}

/// شريط الدور للعبة بالأدوار (يظهر تحت للاعب الأول وفوق مقلوب للثاني)
class TurnBadge extends StatelessWidget {
  const TurnBadge({super.key, required this.player, required this.active, required this.score, this.label});
  final int player;
  final bool active;
  final int score;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = C.players[player];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: alpha(c, active ? 0.22 : 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: alpha(c, active ? 0.9 : 0.25), width: active ? 2.0 : 1.0),
        boxShadow: active ? [BoxShadow(color: alpha(c, 0.35), blurRadius: 20)] : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            label ?? (active ? 'دورك' : C.playerNames[player]),
            style: body(18, weight: FontWeight.w800, color: active ? Colors.white : C.muted),
          ),
          const SizedBox(width: 14),
          Text('$score', style: display(26, color: c)),
        ],
      ),
    );
  }
}
