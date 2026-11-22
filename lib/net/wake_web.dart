// الويب: الآيفون ما يبلّغ دائماً إن الصفحة رجعت (بعد قفل التلفون أو التبديل بين التطبيقات)،
// والاتصال يموت بصمت. هنا نراقب رجوع الصفحة مباشرة حتى نرجع نتصل فوراً.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// يستدعي [cb] كل ما ترجع الصفحة ظاهرة. يرجّع دالة تلغي المراقبة.
void Function() onPageBack(void Function() cb) {
  void visible(web.Event _) {
    if (web.document.visibilityState == 'visible') cb();
  }

  void any(web.Event _) => cb();

  final v = visible.toJS, a = any.toJS;
  web.document.addEventListener('visibilitychange', v);
  web.window.addEventListener('pageshow', a);
  web.window.addEventListener('focus', a);
  web.window.addEventListener('online', a);
  return () {
    web.document.removeEventListener('visibilitychange', v);
    web.window.removeEventListener('pageshow', a);
    web.window.removeEventListener('focus', a);
    web.window.removeEventListener('online', a);
  };
}
