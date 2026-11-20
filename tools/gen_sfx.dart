// يولّد أصوات وموسيقى اللعبة بالكود (بدون ملفات جاهزة) ويحفظها بـ assets/sfx/
// التشغيل: dart run tools/gen_sfx.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const rate = 22050;
final rnd = math.Random(7);

class Track {
  Track(double sec, {this.wrap = false}) : b = List.filled((sec * rate).round(), 0.0);
  final List<double> b;

  /// للموسيقى: الذيل يلف لبداية الملف حتى اللوب يصير بدون قطع
  final bool wrap;

  void add(int i, double v) {
    if (wrap) {
      b[i % b.length] += v;
    } else if (i < b.length) {
      b[i] += v;
    }
  }
}

double env(double t, double attack, double decay) {
  if (t < attack) return t / attack;
  return math.exp(-(t - attack) / decay);
}

/// نغمة بتردد يتغير (f0 → f1). harm = توافقيات، vib = اهتزاز التردد
void tone(Track tr, double start, double dur, double f0, double f1, double vol,
    {double attack = 0.005, double decay = 0.1, double harm = 0, double vib = 0, double vibHz = 6, double square = 0}) {
  var phase = 0.0;
  final n = (dur * rate).round();
  final s0 = (start * rate).round();
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    final f = f0 * math.pow(f1 / f0, i / n) + vib * math.sin(2 * math.pi * vibHz * t);
    phase += 2 * math.pi * f / rate;
    var v = math.sin(phase) + harm * math.sin(phase * 2) + harm * 0.5 * math.sin(phase * 3);
    if (square > 0) v = v * (1 - square) + square * (math.sin(phase) >= 0 ? 0.7 : -0.7);
    tr.add(s0 + i, v * vol * env(t, attack, decay));
  }
}

/// ضجيج: smooth صغير = غامق، كبير = حاد. hp = يشيل الواطي (أحد)
void noise(Track tr, double start, double dur, double vol,
    {double smooth = 0.3, double attack = 0.002, double decay = 0.05, double am = 0, bool hp = false, double sweep = 0}) {
  final n = (dur * rate).round();
  final s0 = (start * rate).round();
  var y = 0.0, prev = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / rate;
    final sm = (smooth + sweep * (i / n)).clamp(0.01, 1.0);
    y += (rnd.nextDouble() * 2 - 1 - y) * sm;
    var v = y;
    if (hp) {
      v = y - prev;
      prev = y;
    }
    final mod = am > 0 ? 0.5 + 0.5 * math.sin(2 * math.pi * am * t) : 1.0;
    tr.add(s0 + i, v * vol * env(t, attack, decay) * mod);
  }
}

/// صدى خفيف حتى الصوت يصير أنعم وأوسع
void reverb(Track tr, {double mix = 0.25}) {
  final b = tr.b;
  final out = List<double>.from(b);
  for (final (d, g) in [(0.029, 0.5), (0.037, 0.45), (0.053, 0.4), (0.071, 0.33)]) {
    final dl = (d * rate).round();
    final line = List<double>.filled(b.length, 0);
    for (var i = 0; i < b.length; i++) {
      final back = i - dl;
      final fb = back >= 0 ? line[back] : (tr.wrap ? line[(back + b.length) % b.length] : 0.0);
      line[i] = b[i] + fb * g;
      out[i] += (line[i] - b[i]) * mix * 0.5;
    }
  }
  for (var i = 0; i < b.length; i++) {
    b[i] = out[i];
  }
}

void save(String name, Track tr, {double peakTo = 0.9}) {
  final b = tr.b;
  var peak = 0.0;
  for (final v in b) {
    peak = math.max(peak, v.abs());
  }
  final norm = peak > 0 ? peakTo / peak : 1.0;
  if (!tr.wrap) {
    final fade = math.min(300, b.length);
    for (var i = 0; i < fade; i++) {
      b[b.length - 1 - i] *= i / fade;
    }
  }
  final data = ByteData(44 + b.length * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + b.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, b.length * 2, Endian.little);
  for (var i = 0; i < b.length; i++) {
    // ضغط ناعم حتى الأصوات العالية ما تتشوّه
    final v = _soft(b[i] * norm);
    data.setInt16(44 + i * 2, (v * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  File('assets/sfx/$name.wav')
    ..createSync(recursive: true)
    ..writeAsBytesSync(data.buffer.asUint8List());
  stdout.writeln('assets/sfx/$name.wav  ${(b.length / rate).toStringAsFixed(2)}s');
}

double _soft(double x) => x.abs() < 0.7 ? x : x.sign * (0.7 + 0.3 * (1 - math.exp(-(x.abs() - 0.7) * 3)));

// ------------------------------------------------------------------ مؤثرات

void effects() {
  // شد المطاطة: صرير خفيف يصعد
  var t = Track(0.22);
  tone(t, 0, 0.22, 90, 150, 0.45, attack: 0.04, decay: 0.12, harm: 0.8, vib: 6, vibHz: 40);
  noise(t, 0, 0.2, 0.2, smooth: 0.1, attack: 0.03, decay: 0.1);
  save('stretch', t, peakTo: 0.7);

  // رمية المصيادة: طقّة مطاط + هوا
  t = Track(0.3);
  noise(t, 0, 0.025, 0.9, smooth: 0.7, decay: 0.008);
  tone(t, 0, 0.16, 260, 70, 0.8, decay: 0.045, harm: 0.4);
  noise(t, 0.01, 0.28, 0.45, smooth: 0.05, attack: 0.02, decay: 0.09, sweep: 0.35, hp: true);
  save('snap', t);

  // إصابة الحمامة: طخّة + صيحة + ريش يرفرف
  t = Track(0.5);
  tone(t, 0, 0.14, 160, 55, 1.0, decay: 0.045);
  noise(t, 0, 0.05, 0.8, smooth: 0.45, decay: 0.015);
  tone(t, 0.02, 0.14, 1100, 650, 0.35, attack: 0.01, decay: 0.05, harm: 0.6, vib: 60, vibHz: 45);
  noise(t, 0.04, 0.42, 0.55, smooth: 0.22, attack: 0.01, decay: 0.16, am: 26, hp: true);
  reverb(t, mix: 0.2);
  save('hit', t);

  // الذهبية: جرس لامع وصدى
  t = Track(1.0);
  for (final (i, f) in [1318.5, 1760.0, 2093.0, 2637.0].indexed) {
    tone(t, i * 0.06, 0.8, f, f, 0.45, decay: 0.22, harm: 0.12);
    tone(t, i * 0.06, 0.5, f * 2.01, f * 2.01, 0.1, decay: 0.08);
  }
  reverb(t, mix: 0.45);
  save('gold', t);

  // الغراب: گاق خشن
  t = Track(0.5);
  tone(t, 0, 0.32, 560, 380, 0.65, attack: 0.015, decay: 0.14, harm: 1.0, vib: 55, vibHz: 33, square: 0.4);
  noise(t, 0, 0.32, 0.4, smooth: 0.35, attack: 0.01, decay: 0.13);
  reverb(t, mix: 0.15);
  save('crow', t);

  // الحجارة تطيح على السطح
  t = Track(0.16);
  noise(t, 0, 0.14, 0.9, smooth: 0.18, decay: 0.03);
  tone(t, 0, 0.08, 320, 160, 0.45, decay: 0.022);
  tone(t, 0.05, 0.05, 280, 180, 0.2, decay: 0.015);
  save('land', t, peakTo: 0.75);

  // حجارتين تتصادم بالجو
  t = Track(0.2);
  tone(t, 0, 0.12, 2700, 2300, 0.6, attack: 0.001, decay: 0.025);
  tone(t, 0, 0.12, 4100, 3600, 0.3, attack: 0.001, decay: 0.018);
  noise(t, 0, 0.04, 0.6, smooth: 0.9, decay: 0.01, hp: true);
  reverb(t, mix: 0.25);
  save('clack', t);

  // قوة: صعود لامع
  t = Track(0.55);
  tone(t, 0, 0.35, 380, 1300, 0.55, attack: 0.01, decay: 0.25, harm: 0.4, square: 0.3);
  tone(t, 0.1, 0.3, 760, 2200, 0.25, attack: 0.01, decay: 0.15);
  for (final (i, f) in [1568.0, 2093.0].indexed) {
    tone(t, 0.28 + i * 0.07, 0.25, f, f, 0.3, decay: 0.08);
  }
  reverb(t, mix: 0.35);
  save('power', t);

  // تجميد: بلّور بارد
  t = Track(0.9);
  for (final (i, f) in [2093.0, 2637.0, 3136.0, 2349.0, 2793.0].indexed) {
    tone(t, i * 0.045, 0.6, f, f * 0.93, 0.3, decay: 0.16, vib: 20, vibHz: 14);
  }
  noise(t, 0, 0.6, 0.18, smooth: 0.95, decay: 0.2, hp: true);
  reverb(t, mix: 0.5);
  save('freeze', t);

  // كومبو: أربع نغمات صاعدة
  t = Track(0.7);
  for (final (i, f) in [587.3, 740.0, 880.0, 1174.7].indexed) {
    tone(t, i * 0.07, 0.25, f, f, 0.5, decay: i == 3 ? 0.14 : 0.06, harm: 0.3, square: 0.25);
  }
  reverb(t, mix: 0.35);
  save('combo', t);

  // هديل الحمامة: كرّو... كوو
  t = Track(1.0);
  tone(t, 0.0, 0.36, 330, 285, 0.55, attack: 0.07, decay: 0.2, harm: 0.3, vib: 14, vibHz: 24);
  tone(t, 0.4, 0.5, 300, 245, 0.55, attack: 0.09, decay: 0.24, harm: 0.3, vib: 10, vibHz: 20);
  noise(t, 0, 0.9, 0.05, smooth: 0.05, decay: 0.4);
  reverb(t, mix: 0.2);
  save('coo', t, peakTo: 0.7);

  // رفرفة جنحان (حمامة جديدة)
  t = Track(0.45);
  for (var i = 0; i < 5; i++) {
    noise(t, i * 0.075, 0.07, 0.6 - i * 0.08, smooth: 0.25, attack: 0.01, decay: 0.03, hp: true);
  }
  save('flap', t, peakTo: 0.7);

  // سرب يمر: هوا عابر
  t = Track(0.9);
  noise(t, 0, 0.9, 0.7, smooth: 0.04, attack: 0.3, decay: 0.25, sweep: 0.3, am: 18);
  save('whoosh', t, peakTo: 0.7);

  // تك الثواني الأخيرة
  t = Track(0.1);
  tone(t, 0, 0.08, 1800, 1700, 0.6, attack: 0.001, decay: 0.02);
  tone(t, 0, 0.06, 900, 880, 0.3, attack: 0.001, decay: 0.02);
  save('tick', t, peakTo: 0.6);

  // صندوق يطلع: بوب
  t = Track(0.3);
  tone(t, 0, 0.18, 300, 900, 0.6, attack: 0.003, decay: 0.07, harm: 0.3);
  reverb(t, mix: 0.25);
  save('pop', t, peakTo: 0.7);

  // الفوز: فانفار
  t = Track(1.6);
  for (final (i, f) in [523.3, 659.3, 784.0].indexed) {
    tone(t, i * 0.12, 0.2, f, f, 0.5, decay: 0.08, harm: 0.3, square: 0.3);
  }
  for (final f in [523.3, 659.3, 784.0, 1046.5]) {
    tone(t, 0.4, 1.1, f, f, 0.35, attack: 0.01, decay: 0.45, harm: 0.3, square: 0.2, vib: 4, vibHz: 6);
  }
  noise(t, 0.4, 0.3, 0.3, smooth: 0.9, decay: 0.12, hp: true);
  reverb(t, mix: 0.4);
  save('win', t);
}

// ------------------------------------------------------------------ موسيقى

/// دمّ: ضربة الدربكة الواطية
void doum(Track t, double at, double vol) {
  tone(t, at, 0.3, 120, 70, vol, attack: 0.002, decay: 0.09);
  noise(t, at, 0.03, vol * 0.3, smooth: 0.3, decay: 0.01);
}

/// تك: ضربة الدربكة الحادة
void tek(Track t, double at, double vol) {
  tone(t, at, 0.06, 900, 700, vol * 0.5, attack: 0.001, decay: 0.015);
  noise(t, at, 0.06, vol, smooth: 0.8, decay: 0.018, hp: true);
}

void kick(Track t, double at, double vol) {
  tone(t, at, 0.22, 150, 42, vol, attack: 0.001, decay: 0.07);
  noise(t, at, 0.01, vol * 0.4, smooth: 0.9, decay: 0.003);
}

void clap(Track t, double at, double vol) {
  for (var i = 0; i < 3; i++) {
    noise(t, at + i * 0.008, 0.12, vol * (i == 2 ? 1 : 0.5), smooth: 0.55, decay: i == 2 ? 0.05 : 0.008, hp: true);
  }
}

void hat(Track t, double at, double vol, {bool open = false}) {
  noise(t, at, open ? 0.18 : 0.05, vol, smooth: 0.95, decay: open ? 0.06 : 0.014, hp: true);
}

void pluck(Track t, double at, double f, double vol, {double decay = 0.14}) {
  tone(t, at, decay * 4, f, f, vol, attack: 0.003, decay: decay, harm: 0.35, square: 0.15);
  tone(t, at, decay * 2, f * 2, f * 2, vol * 0.15, attack: 0.002, decay: decay * 0.5);
}

/// مقام حجاز على ري
const hijaz = [293.7, 311.1, 370.0, 392.0, 440.0, 466.2, 523.3, 587.3, 622.3, 740.0];

void song(String name, {required double bpm, required bool crazy}) {
  final beat = 60 / bpm;
  const bars = 8;
  final t = Track(bars * 4 * beat, wrap: true);
  final eighth = beat / 2, six = beat / 4;

  // البيز: ري ري دو ري / مي♭ ري دو ري
  const roots = [73.4, 73.4, 65.4, 73.4, 77.8, 73.4, 65.4, 73.4];
  // لحن قصير يتكرر كل بارين (درجات من المقام)
  const motifA = [0, 2, 3, 4, 3, 2, 1, 0, 2, 4, 5, 4, 3, 2, 3, 2];
  const motifB = [4, 5, 6, 7, 6, 5, 4, 3, 4, 3, 2, 1, 2, 1, 0, -1];

  for (var bar = 0; bar < bars; bar++) {
    final b0 = bar * 4 * beat;
    // مقسوم: دم تك - تك دم - تك -
    final maqsum = <(int, bool)>[(0, true), (1, false), (3, false), (4, true), (6, false)];
    for (final (e, isDoum) in maqsum) {
      final at = b0 + e * eighth;
      if (isDoum) {
        doum(t, at, crazy ? 0.75 : 0.6);
      } else {
        tek(t, at, crazy ? 0.45 : 0.35);
      }
    }
    // تك صغيرة بين الضربات
    for (final e in [2, 5, 7]) {
      tek(t, b0 + e * eighth + (crazy ? 0 : six), 0.14);
    }
    if (crazy) {
      for (var q = 0; q < 4; q++) {
        kick(t, b0 + q * beat, 0.7);
        hat(t, b0 + q * beat + eighth, 0.22, open: q == 3);
      }
      clap(t, b0 + beat, 0.5);
      clap(t, b0 + 3 * beat, 0.5);
      for (var s = 0; s < 16; s++) {
        if (s % 2 == 1) hat(t, b0 + s * six, 0.1);
      }
    }

    // البيز
    final root = roots[bar];
    final bassPattern = crazy ? [0, 3, 4, 6, 7] : [0, 4];
    for (final e in bassPattern) {
      final f = (e == 3 || e == 7) ? root * 2 : root;
      tone(t, b0 + e * eighth, eighth * 1.6, f, f, crazy ? 0.5 : 0.42,
          attack: 0.005, decay: eighth * 0.9, harm: 0.5, square: crazy ? 0.35 : 0.1);
    }

    // اللحن
    final motif = bar.isEven ? motifA : motifB;
    final step = crazy ? six : eighth;
    final count = crazy ? 16 : 8;
    for (var i = 0; i < count; i++) {
      final deg = motif[crazy ? i : i * 2];
      if (!crazy && i == 7 && bar % 4 == 3) continue;
      final f = deg < 0 ? hijaz[0] * 0.75 : hijaz[deg % hijaz.length];
      pluck(t, b0 + i * step, f, crazy ? 0.22 : 0.26, decay: crazy ? 0.08 : 0.16);
    }

    // نغمة طويلة بالخلفية (پاد) حتى يصير الصوت مليان
    tone(t, b0, 4 * beat, root * 4, root * 4, 0.08, attack: 0.4, decay: 3 * beat, harm: 0.2, vib: 2, vibHz: 5);
    tone(t, b0, 4 * beat, root * 6, root * 6, 0.05, attack: 0.5, decay: 3 * beat, vib: 2, vibHz: 4.5);
  }
  reverb(t, mix: crazy ? 0.18 : 0.28);
  save(name, t, peakTo: 0.85);
}

void main() {
  effects();
  song('music_calm', bpm: 96, crazy: false);
  song('music_crazy', bpm: 132, crazy: true);
}
