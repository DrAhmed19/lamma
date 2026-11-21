// روابط الدعوة وواتساب وشريط "حمّل التطبيق"
//
// الرابط: <الويب>/j/CODE (و /j/ بدون غرفة). دالة Pages (functions/j/) تطلع بطاقة واتساب
// وتحوّل للويب، وأندرويد اللي عنده التطبيق ينفتح التطبيق مباشرة (App Links، tools/patch_android.py).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/updater.dart';
import '../games/registry.dart';
import '../net/room.dart';
import 'kit.dart';
import 'theme.dart';

/// لون واتساب
const kWhatsApp = Color(0xFF25D366);

String get _webBase => kIsWeb && lanOrigin == null ? Uri.base.origin : kWebUrl;

/// رابط دعوة لغرفة (أونلاين)
String roomInviteLink(String code) => '$_webBase/j/$code';

/// رسالة الدعوة لغرفة
String roomInviteText(String code, {String? gameId}) {
  final g = gameById(gameId);
  final what = g == null ? '' : ' ${g.title}';
  return 'تعال العب وياي$what بلمّة! 🎮\n${roomInviteLink(code)}';
}

/// دعوة للمّة بدون غرفة
String get appInviteText => 'تعال العب وياي بلمّة! 🎮\n$_webBase/j/';

/// يفتح واتساب والرسالة جاهزة. إذا ما انفتح: نافذة المشاركة العادية.
Future<void> sendWhatsApp(String text) async {
  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (ok) return;
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (_) {}
}

/// زر "ادعُ عبر واتساب"
class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton({super.key, required this.label, required this.text});
  final String label;
  final String Function() text;

  @override
  Widget build(BuildContext context) {
    return BigButton(label: label, icon: Icons.chat_rounded, color: kWhatsApp, onTap: () => sendWhatsApp(text()));
  }
}

/// شريط صغير بالويب على أندرويد: "حمّل التطبيق". يختفي إذا تجاهله وما يرجع.
/// (الآيفون ماكو إله تطبيق، يبقى على الويب)
class GetAppBanner extends StatefulWidget {
  const GetAppBanner({super.key, this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 0)});
  final EdgeInsets padding;

  static bool get applies => kIsWeb && lanOrigin == null && defaultTargetPlatform == TargetPlatform.android;

  @override
  State<GetAppBanner> createState() => _GetAppBannerState();
}

class _GetAppBannerState extends State<GetAppBanner> {
  static const _key = 'app_banner_off';
  static bool _off = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (GetAppBanner.applies && !_off) _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _off = p.getBool(_key) ?? false;
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _dismiss() async {
    setState(() => _off = true);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!GetAppBanner.applies || _off || !_ready) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: alpha(C.accent, 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: alpha(C.accent, 0.45)),
        ),
        child: Row(
          children: [
            const Icon(Icons.android_rounded, color: Color(0xFF22D37E), size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('اللعب أسلس في التطبيق', style: body(14, weight: FontWeight.w700))),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(kApkUrl), mode: LaunchMode.externalApplication),
              child: Text('حمّل التطبيق', style: body(14, weight: FontWeight.w800, color: const Color(0xFFC9B8FF))),
            ),
            IconButton(
              onPressed: _dismiss,
              visualDensity: VisualDensity.compact,
              tooltip: 'إخفاء',
              icon: const Icon(Icons.close_rounded, color: C.muted, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
