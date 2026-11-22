// بالتطبيق (مو ويب): الأصوات تشتغل بـ audioplayers عادي، فهذا فارغ.
class WebAudio {
  static bool get available => false;
  static void preload(String name) {}
  static void play(String name, double volume) {}
  static void playMusic(String name, double volume) {}
  static void pauseMusic() {}
  static void resumeMusic() {}
  static void stopMusic() {}
}
