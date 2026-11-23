import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/pwa_stub.dart' if (dart.library.js_interop) '../core/pwa_web.dart';
import '../net/room.dart' show lanOrigin;
import 'kit.dart';
import 'theme.dart';

/// الويب بس: «ثبّت التطبيق» (كروم/سامسونج/إيدج)، أو تعليمات لمرة وحدة (الآيفون: مشاركة ← إضافة إلى الشاشة الرئيسية،
/// وفايرفوكس: من القائمة). يختفي إذا اللعبة مثبّتة وتشتغل standalone، وبالغرفة المحلية.
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  String kind = 'none';
  bool later = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (lanOrigin != null) return;
    _check();
    // كروم يطلق beforeinstallprompt بعد شوية؛ نعيد الفحص كم مرة
    var n = 0;
    _t = Timer.periodic(const Duration(seconds: 2), (t) {
      if (++n > 10 || kind == 'prompt') t.cancel();
      _check();
    });
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => later = p.getBool('pwa_later') ?? false);
    });
  }

  void _check() {
    final k = pwaKind();
    if (k != kind && mounted) setState(() => kind = k);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _later() async {
    setState(() => later = true);
    try {
      (await SharedPreferences.getInstance()).setBool('pwa_later', true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (kind == 'none') return const SizedBox.shrink();
    // زر التثبيت يبقى دائماً؛ التعليمات لمرة وحدة (إلى أن يضغط «لاحقاً»)
    if (kind != 'prompt' && later) return const SizedBox.shrink();
    final text = switch (kind) {
      'prompt' => 'ثبّت لمّة على هاتفك وافتحها مثل أي تطبيق',
      'ios' => 'لتثبيت لمّة: اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية»',
      _ => 'لتثبيت لمّة: افتح قائمة المتصفح ثم «تثبيت» أو «إضافة إلى الشاشة الرئيسية»',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: L.sky2, offset: Offset(0, 5))]),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: const Color(0xFF2E9BF0), borderRadius: BorderRadius.circular(14)),
              child: Icon(kind == 'ios' ? Icons.ios_share_rounded : Icons.install_mobile_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: body(13.5, weight: FontWeight.w800, color: L.ink))),
            const SizedBox(width: 8),
            if (kind == 'prompt')
              ChunkyButton(label: 'ثبّت', color: const Color(0xFF3DB56E), onTap: () {
                pwaInstall();
                Future.delayed(const Duration(seconds: 3), _check);
              })
            else
              TextButton(onPressed: _later, child: Text('لاحقاً', style: body(14, weight: FontWeight.w900, color: L.muted))),
          ],
        ),
      ),
    );
  }
}
