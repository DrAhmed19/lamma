// الويب: الأصوات بـ WebAudio بدل عناصر <audio>.
// سفاري الآيفون يتقطع وياها (كل تشغيل يثقّل الشاشة، فكانت الحمامة تنزل لـ24 إطار لمّن تسحب وترمي).
// هنا كل صوت ينفك مرة وحدة لذاكرة، وبعدها التشغيل خفيف جداً والأصوات تتداخل عادي.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

class WebAudio {
  static web.AudioContext? _ctx;
  static bool _failed = false;
  static final Map<String, web.AudioBuffer> _buffers = {};
  static final Map<String, Future<web.AudioBuffer?>> _loading = {};

  static bool get available => _context != null;

  static web.AudioContext? get _context {
    if (_ctx != null || _failed) return _ctx;
    try {
      _ctx = web.AudioContext();
      _unlockOnTouch();
      // الآيفون: الصوت يطلع حتى لو التلفون على الصامت (مثل الألعاب)
      try {
        final session = (web.window.navigator as JSObject)['audioSession'];
        if (session != null && session.isA<JSObject>()) (session as JSObject)['type'] = 'playback'.toJS;
      } catch (_) {}
    } catch (_) {
      _failed = true;
    }
    return _ctx;
  }

  /// المتصفح ما يسمح بالصوت إلا بعد لمسة: أول لمسة تشغّله
  static void _unlockOnTouch() {
    void unlock(web.Event _) {
      final c = _ctx;
      if (c == null || c.state == 'running') return;
      try {
        c.resume();
        // الآيفون القديم يحتاج صوت فارغ يشتغل داخل اللمسة نفسها
        final src = c.createBufferSource()..buffer = c.createBuffer(1, 1, 22050);
        src.connect(c.destination);
        src.start();
      } catch (_) {}
    }

    final opts = web.AddEventListenerOptions(capture: true, passive: true);
    for (final t in const ['pointerdown', 'touchend', 'keydown', 'click']) {
      web.document.addEventListener(t, unlock.toJS, opts);
    }
  }

  static Future<web.AudioBuffer?> _load(String name) {
    final b = _buffers[name];
    if (b != null) return Future.value(b);
    return _loading.putIfAbsent(name, () async {
      final c = _context;
      if (c == null) return null;
      try {
        final data = await rootBundle.load('assets/sfx/$name.wav');
        // نسخة خاصة: decodeAudioData يستهلك المصفوفة
        final bytes = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        final buf = await c.decodeAudioData(bytes.buffer.toJS).toDart;
        _buffers[name] = buf;
        return buf;
      } catch (_) {
        _loading.remove(name);
        return null;
      }
    });
  }

  static void preload(String name) => unawaited(_load(name));

  static void play(String name, double volume) {
    final c = _context;
    if (c == null) return;
    final buf = _buffers[name];
    if (buf == null) {
      // أول مرة: نحمّله هسه ونشغّله إذا جهز بسرعة (أقل من ربع ثانية)
      final asked = DateTime.now();
      unawaited(_load(name).then((b) {
        if (b != null && DateTime.now().difference(asked).inMilliseconds < 250) _start(c, b, volume);
      }));
      return;
    }
    _start(c, buf, volume);
  }

  static web.AudioBufferSourceNode _start(web.AudioContext c, web.AudioBuffer buf, double volume, {bool loop = false, double offset = 0}) {
    final gain = c.createGain();
    gain.gain.value = volume;
    gain.connect(c.destination);
    final src = c.createBufferSource()
      ..buffer = buf
      ..loop = loop;
    src.connect(gain);
    src.start(0, offset);
    return src;
  }

  // ------------------------------------------------------------ الموسيقى

  static web.AudioBufferSourceNode? _music;
  static String? _musicName;
  static double _musicVol = 0.35, _musicAt = 0, _musicOffset = 0;
  static bool _musicOn = false;
  static int _token = 0;

  static void _stopSource() {
    try {
      _music?.stop();
    } catch (_) {}
    _music = null;
  }

  static void playMusic(String name, double volume) {
    final c = _context;
    if (c == null) return;
    final t = ++_token;
    _stopSource();
    _musicName = name;
    _musicVol = volume;
    _musicOffset = 0;
    _musicOn = true;
    unawaited(_load(name).then((b) {
      if (b == null || t != _token || !_musicOn) return;
      _music = _start(c, b, volume, loop: true);
      _musicAt = c.currentTime;
    }));
  }

  static void pauseMusic() {
    final c = _ctx;
    final b = _musicName == null ? null : _buffers[_musicName];
    if (c == null || !_musicOn) return;
    _musicOn = false;
    if (_music != null && b != null && b.duration > 0) {
      _musicOffset = (_musicOffset + c.currentTime - _musicAt) % b.duration;
    }
    _stopSource();
  }

  static void resumeMusic() {
    final c = _ctx;
    final name = _musicName;
    if (c == null || name == null || _musicOn) return;
    final b = _buffers[name];
    _musicOn = true;
    if (b == null) {
      playMusic(name, _musicVol);
      return;
    }
    _music = _start(c, b, _musicVol, loop: true, offset: _musicOffset);
    _musicAt = c.currentTime;
  }

  static void stopMusic() {
    _token++;
    _musicOn = false;
    _musicName = null;
    _musicOffset = 0;
    _stopSource();
  }
}
