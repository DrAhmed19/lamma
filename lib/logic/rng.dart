/// مولّد أرقام عشوائية بسيط حالته رقم واحد، حتى ينحفظ ويرجع بالضبط
/// (السيرفر والتطبيق ياخذون نفس النتائج من نفس البذرة).
class Rng {
  Rng(int seed) : state = seed & 0xFFFFFFFF;
  int state;

  /// رقم من 0 لـ 1
  double next() {
    state = (state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF;
    t &= 0xFFFFFFFF;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296.0;
  }

  int nextInt(int max) => (next() * max).floor().clamp(0, max - 1);
  bool nextBool() => next() < 0.5;

  static int _imul(int a, int b) {
    // ضرب 32 بت (نفس Math.imul) حتى النتيجة تطابق بالويب والأندرويد
    final ah = (a >>> 16) & 0xFFFF, al = a & 0xFFFF;
    final bh = (b >>> 16) & 0xFFFF, bl = b & 0xFFFF;
    return ((al * bl) + ((((ah * bl) + (al * bh)) << 16) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  }
}
