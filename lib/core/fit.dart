import 'dart:math' as math;
import 'dart:ui';

/// ملعب بنسبة ثابتة ([aspect] = العرض ÷ الطول) يكبر ويصغر بنفس المقياس داخل الشاشة، والزايد يصير خلفية.
///
/// القاعدة لأي لعبة بيها ملعب أو مسافات وتنلعب أونلاين (الهوكي، الحمامة، كرة القدم...):
/// على التلفونات الملعب يملي الشاشة (مرّر [aspect] = نسبة الشاشة بس محصورة بمدى التلفونات،
/// مثلاً 0.42–0.62)، حتى اللعبة تبين كبيرة وحية مثل كلاش رويال. الأعرض من هالمدى (تابلت/كمبيوتر)
/// يوقف عند الحد ويصير عمود بالنص، لأن المطّ الكبير يقرّب الجهات ويكبّر الأهداف ويسهّل اللعب إلهم.
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
