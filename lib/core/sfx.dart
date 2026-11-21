import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// أصوات قصيرة. الملفات تنولد بالكود عبر tools/gen_sfx.dart.
/// كل صوت إله كم مشغّل محمّل مسبقاً، حتى التشغيل يصير فوري وبدون تقطيع،
/// والأصوات تتداخل بدون ما تقطع بعضها.
class Sfx {
  static bool enabled = true;
  static const _voices = 3;
  static final Map<String, List<AudioPlayer>> _pool = {};
  static final Map<String, int> _next = {};

  static AudioPlayer _make(String name) {
    final p = AudioPlayer();
    p.audioCache.prefix = 'assets/sfx/';
    unawaited(() async {
      try {
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource('$name.wav'));
      } catch (_) {}
    }());
    return p;
  }

  /// يحمّل الأصوات قبل اللعب (يتسوّى مرة وحدة)
  static void preload(List<String> names) {
    for (final n in names) {
      _pool.putIfAbsent(n, () => List.generate(_voices, (_) => _make(n)));
    }
  }

  static final Map<String, int> _lastAt = {};
  static final _clock = Stopwatch()..start();

  static void play(String name, {double volume = 1}) {
    if (!enabled) return;
    // نفس الصوت مرتين بأقل من 70ms ما يبين، بس يثقّل (خصوصاً متصفح الآيفون)
    final now = _clock.elapsedMilliseconds;
    if (now - (_lastAt[name] ?? -1000) < 70) return;
    _lastAt[name] = now;
    final ps = _pool.putIfAbsent(name, () => List.generate(_voices, (_) => _make(name)));
    final i = (_next[name] ?? 0) % ps.length;
    _next[name] = i + 1;
    final p = ps[i];
    unawaited(() async {
      try {
        await p.stop();
        await p.setVolume(volume);
        await p.resume();
      } catch (_) {
        // الصوت مو ضروري للعب، إذا فشل نكمل بصمت
      }
    }());
  }
}

/// موسيقى الخلفية (تلف بدون توقف)
class Music {
  static AudioPlayer? _p;
  static String? _current;

  static void play(String name, {double volume = 0.35}) {
    if (!Sfx.enabled) return;
    unawaited(() async {
      try {
        final p = _p ??= AudioPlayer()..audioCache.prefix = 'assets/sfx/';
        if (_current != name) {
          await p.stop();
          await p.setReleaseMode(ReleaseMode.loop);
          await p.setSource(AssetSource('$name.wav'));
          _current = name;
        } else {
          await p.seek(Duration.zero);
        }
        await p.setVolume(volume);
        await p.resume();
      } catch (_) {}
    }());
  }

  static void pause() => _safe((p) => p.pause());
  static void resume() => _safe((p) => p.resume());
  static void stop() => _safe((p) => p.stop());

  static void _safe(Future<void> Function(AudioPlayer p) f) {
    final p = _p;
    if (p == null) return;
    unawaited(() async {
      try {
        await f(p);
      } catch (_) {}
    }());
  }
}
