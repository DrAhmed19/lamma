// تثبيت الويب كتطبيق: يقرا window.lammaPwa (من patch_web.py بـ index.html)
import 'dart:js_interop';

@JS('lammaPwa')
external _Pwa? get _pwa;

extension type _Pwa(JSObject _) implements JSObject {
  external bool standalone();
  external String kind();
  external void install();
}

/// 'prompt' (كروم وأشباهه: زر تثبيت)، 'ios' (تعليمات المشاركة)، 'menu' (تعليمات القائمة)، 'none'
String pwaKind() {
  try {
    final p = _pwa;
    if (p == null || p.standalone()) return 'none';
    return p.kind();
  } catch (_) {
    return 'none';
  }
}

void pwaInstall() {
  try {
    _pwa?.install();
  } catch (_) {}
}
