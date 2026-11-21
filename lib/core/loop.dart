import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ui/kit.dart';

enum GamePhase { countdown, play, over }

/// أساس كل لعبة: حلقة إطارات ثابتة (60/120 إطار) مع إيقاف مؤقت.
abstract class LoopState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin<T> {
  late final Ticker _ticker;

  /// يتغير كل إطار حتى يعيد الرسام الرسم.
  final ValueNotifier<int> frame = ValueNotifier<int>(0);
  Duration _last = Duration.zero;

  /// الوقت بالثواني منذ بداية اللعبة (لا يحسب وقت الإيقاف).
  double time = 0;
  bool paused = false;

  /// أونلاين: وصلت أول حالة من السيرفر؟ (كل لعبة تحددها)
  bool get ready => true;
  bool? _wasReady;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (dt < 0) dt = 0;
    if (!paused) {
      time += dt;
      update(dt);
    }
    frame.value++;
    // أول ما توصل حالة السيرفر نعيد بناء الشاشة، حتى ما تبقى على "جارٍ الاتصال"
    // (قبل كانت تفتح بس بعد الإيقاف المؤقت لأن هو اللي يعيد البناء)
    final r = ready;
    if (r != _wasReady) {
      final first = _wasReady == null;
      _wasReady = r;
      if (!first && mounted) setState(() {});
    }
  }

  void update(double dt);

  /// يرجع اللعبة لبدايتها.
  void restart();

  Future<void> openPause() async {
    if (paused) return;
    setState(() => paused = true);
    final action = await showPauseMenu(context);
    if (!mounted) return;
    setState(() => paused = false);
    if (action == PauseAction.restart) {
      restart();
    } else if (action == PauseAction.exit) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    frame.dispose();
    super.dispose();
  }
}
