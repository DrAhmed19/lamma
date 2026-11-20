# لمّة (Lamma) — ملاحظات للمطوّر

- Flutter واحد يطلع منه **ويب** (لجماعة الآيفون) و**APK** أندرويد أصلي.
- مجلدات `android/` و `web/` ما تنحفظ بالريبو؛ تنولد بالبناء عبر `tools/prepare.sh` (اسم، أيقونة، شاشة تحميل، شاشة تبقى شغالة).
- البناء: `.github/workflows/build.yml`
  - كل push على main: تحليل + بناء ويب + نشر على Cloudflare Pages (مشروع `lamma`) بحساب Cloudflare المستقل للعبة (secrets: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID).
  - الـ APK بس إذا رسالة الـ commit بيها `[apk]` أو تشغيل يدوي → Release باسم `apk-latest`.
  - مفتاح التوقيع الثابت `ci/debug.keystore` (حتى التحديث ينزل فوق القديم).
- الكود:
  - `lib/core/loop.dart` حلقة الإطارات + الإيقاف المؤقت لكل لعبة.
  - `lib/ui/kit.dart` العد التنازلي، شاشة النتيجة، قائمة الإيقاف، الأزرار.
  - `lib/games/` كل لعبة بملف، وتنضاف لـ `registry.dart`.
  - الرسوم كلها بالكود (CustomPainter) بدون صور.
- الخط: Tajawal للنصوص و Lalezar للعناوين (داخل assets/fonts).
- القادم: اللعب أونلاين بغرف وكود (Cloudflare Workers + Durable Objects)، ثم الواي فاي المحلي للأندرويد.
