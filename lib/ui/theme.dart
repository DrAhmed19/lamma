import 'package:flutter/material.dart';

const kFont = 'Tajawal';
const kDisplay = 'Lalezar';

/// ألوان التطبيق
class C {
  static const bg = Color(0xFF090C18);
  static const bg2 = Color(0xFF141A33);
  static const surface = Color(0xFF151C36);
  static const surface2 = Color(0xFF1D2547);
  static const line = Color(0x22FFFFFF);
  static const text = Color(0xFFF4F6FF);
  static const muted = Color(0xFF8C95B8);
  static const accent = Color(0xFF8B6CFF);
  static const go = Color(0xFF2BE38A);

  static const players = [
    Color(0xFFFF4D6A), // أحمر
    Color(0xFF3D8BFF), // أزرق
    Color(0xFF22D37E), // أخضر
    Color(0xFFFFB627), // أصفر
  ];
  static const playerNames = ['الأحمر', 'الأزرق', 'الأخضر', 'الأصفر'];
}

Color lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;
Color alpha(Color c, double a) => c.withValues(alpha: a);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.accent,
    brightness: Brightness.dark,
  ).copyWith(surface: C.surface, primary: C.accent);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: kFont,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    splashFactory: InkRipple.splashFactory,
    textTheme: const TextTheme().apply(
      bodyColor: C.text,
      displayColor: C.text,
      fontFamily: kFont,
    ),
  );
}

TextStyle display(double size, {Color color = C.text, List<Shadow>? shadows}) =>
    TextStyle(
      fontFamily: kDisplay,
      fontSize: size,
      color: color,
      height: 1.15,
      shadows: shadows,
    );

TextStyle body(double size,
        {Color color = C.text, FontWeight weight = FontWeight.w500}) =>
    TextStyle(
      fontFamily: kFont,
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.35,
    );
