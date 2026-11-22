import 'dart:math' as math;
import 'dart:ui';

/// ملعب بنسبة ثابتة ([aspect] = العرض ÷ الطول) يكبر ويصغر بنفس المقياس داخل الشاشة، والزايد يصير خلفية.
///
/// القاعدة لأي لعبة بيها ملعب أو مسافات وتنلعب أونلاين (الهوكي، الحمامة، كرة القدم...):
/// لا تمطّ العالم على الشاشة (عرض بمقياس وطول بمقياس ثاني)، لأن وقتها الشاشات القصيرة أو
/// العريضة (خصوصاً الكمبيوتر) تقرّب الجهات من بعض وتكبّر الأهداف، واللعب يصير أسهل إلهم.
/// بهالدالة الكل يشوف نفس الملعب ونفس المسافات مهما كان حجم الشاشة.
Rect fitField(Size screen, double aspect, {double margin = 0}) {
  final aw = math.max(0.0, screen.width - 2 * margin), ah = math.max(0.0, screen.height - 2 * margin);
  var w = aw, h = aspect > 0 ? aw / aspect : ah;
  if (h > ah) {
    h = ah;
    w = ah * aspect;
  }
  return Rect.fromLTWH((screen.width - w) / 2, (screen.height - h) / 2, w, h);
}
