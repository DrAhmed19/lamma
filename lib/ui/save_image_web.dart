// الويب: نحفظ الصورة كملف (إذا المتصفح ما يدعم مشاركة الملفات)
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> saveImage(Uint8List bytes, String name) async {
  try {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body?.append(a);
    a.click();
    a.remove();
    Future.delayed(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
    return true;
  } catch (_) {
    return false;
  }
}
