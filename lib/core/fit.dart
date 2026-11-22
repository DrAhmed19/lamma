import 'dart:math' as math;
import 'dart:ui';

/// ملعب بنسبة ثابتة ([aspect] = العرض ÷ الطول) يكبر ويصغر بنفس المقياس داخل الشاشة، والزايد يصير خلفية.
///
/// القاعدة لأي لعبة بيها ملعب أو مسافات وتنلعب أونلاين (الهوكي، الحمامة، كرة القدم...):
/// لا تمطّ العالم على الشاشة (عرض بمقياس وطول بمقياس ثاني)، لأن وقتها الشاشات القصيرة أو
/// العريضة (خصوصاً الكمبيوتر) تقرّب الجهات من بعض وتكبّر الأهداف، واللعب يصير أسهل إلهم.
/// بهالدالة الكل يشوف نفس الملعب ونفس المسافات مهما كان حجم الشاشة.
///
/// [dpr] (كثافة الشاشة): إذا انطى، الملعب ينحط على بكسلات الشاشة بالضبط. لازم للألعاب اللي ترسم
/// أشياء ثابتة كصور (toImageSync)، وإلا الصورة تنرسم بنص بكسل وتطلع مغبّشة.
Rect fitField(Size screen, double aspect, {double margin = 0, double dpr = 0}) {
  final aw = math.max(0.0, screen.width - 2 * margin), ah = math.max(0.0, screen.height - 2 * margin);
  var w = aw, h = aspect > 0 ? aw / aspect : ah;
  if (h > ah) {
    h = ah;
    w = ah * aspect;
  }
  var left = (screen.width - w) / 2, top = (screen.height - h) / 2;
  if (dpr > 0) {
    double snap(double v) => (v * dpr).roundToDouble() / dpr;
    w = (w * dpr).floorToDouble() / dpr;
    h = (h * dpr).floorToDouble() / dpr;
    left = snap(left);
    top = snap(top);
  }
  return Rect.fromLTWH(left, top, w, h);
}
