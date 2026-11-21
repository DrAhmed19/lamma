import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../net/room.dart';
import 'kit.dart';
import 'theme.dart';

/// زر التفاعلات السريعة: يفتح قائمة صغيرة (إيموجي وعبارات ثابتة، بدون كتابة حرة)
class ReactButton extends StatelessWidget {
  const ReactButton({super.key, required this.room, this.size = 42});
  final RoomConn room;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: Icons.emoji_emotions_outlined,
      size: size,
      onTap: () => showReactPicker(context, room),
    );
  }
}

Future<void> showReactPicker(BuildContext context, RoomConn room) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: C.line),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < kReactions.length; i++)
                Pressable(
                  onTap: () {
                    room.emo(i);
                    Navigator.pop(ctx);
                  },
                  // بدون alignment: الـ Container ياخذ حجم المحتوى (مو عرض الصف كله)
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 56, minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: alpha(Colors.white, 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.line),
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        kReactions[i],
                        style: kReactions[i].length <= 2 ? const TextStyle(fontSize: 26) : body(15, weight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Floater {
  _Floater(this.text, this.name, this.color, this.x, this.born);
  final String text, name;
  final Color color;
  final double x;
  final DateTime born;
}

/// التفاعلات تطلع وتطير لفوق (فوق اللعبة أو بالغرفة)
class ReactLayer extends StatefulWidget {
  const ReactLayer({super.key, required this.room});
  final RoomConn room;

  @override
  State<ReactLayer> createState() => _ReactLayerState();
}

class _ReactLayerState extends State<ReactLayer> with SingleTickerProviderStateMixin {
  final _items = <_Floater>[];
  final _rnd = math.Random();
  StreamSubscription<NetEmo>? _sub;
  late final AnimationController _tick = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    _sub = widget.room.emos.listen((e) {
      if (!mounted || e.i < 0 || e.i >= kReactions.length) return;
      final name = widget.room.nameOfSeat(e.seat);
      _items.add(_Floater(kReactions[e.i], name, C.players[e.seat.clamp(0, 3)], 0.2 + _rnd.nextDouble() * 0.6, DateTime.now()));
      if (_items.length > 8) _items.removeAt(0);
      if (!_tick.isAnimating) _tick.repeat();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final now = DateTime.now();
        _items.removeWhere((f) => now.difference(f.born).inMilliseconds > 2600);
        if (_items.isEmpty && _tick.isAnimating) _tick.stop();
        return LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              for (final f in _items)
                () {
                  final t = (now.difference(f.born).inMilliseconds / 2600).clamp(0.0, 1.0);
                  final y = box.maxHeight * (0.78 - 0.45 * Curves.easeOut.transform(t));
                  final op = t < 0.75 ? 1.0 : (1 - t) / 0.25;
                  final pop = t < 0.12 ? Curves.easeOutBack.transform(t / 0.12) : 1.0;
                  final isEmoji = f.text.length <= 2;
                  return Positioned(
                    left: box.maxWidth * f.x - 70,
                    top: y,
                    width: 140,
                    child: Opacity(
                      opacity: op.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: pop,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: isEmoji ? 8 : 14, vertical: isEmoji ? 2 : 8),
                              decoration: BoxDecoration(
                                color: isEmoji ? Colors.transparent : alpha(f.color, 0.9),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(f.text,
                                  textAlign: TextAlign.center,
                                  style: isEmoji ? const TextStyle(fontSize: 42) : body(16, weight: FontWeight.w800)),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: alpha(Colors.black, 0.55), borderRadius: BorderRadius.circular(8)),
                              child: Text(f.name, style: body(12, weight: FontWeight.w700, color: lighten(f.color, 0.3))),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
        );
      },
    );
  }
}
