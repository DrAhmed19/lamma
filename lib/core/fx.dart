import 'package:flutter/services.dart';

/// اهتزازات خفيفة للتفاعل
class Fx {
  static void tap() => HapticFeedback.selectionClick();
  static void hit() => HapticFeedback.lightImpact();
  static void mid() => HapticFeedback.mediumImpact();
  static void big() => HapticFeedback.heavyImpact();
}
