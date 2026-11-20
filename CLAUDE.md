# لمّة (Lamma) — ملاحظات للمطوّر

- Flutter واحد يطلع منه **ويب** (لجماعة الآيفون) و**APK** أندرويد أصلي.
- مجلدات `android/` و `web/` ما تنحفظ بالريبو؛ تنولد بالبناء عبر `tools/prepare.sh` (اسم، أيقونة، شاشة تحميل، شاشة تبقى شغالة).
- البناء: `.github/workflows/build.yml`
  - كل push على main: تحليل + بناء ويب + نشر على Cloudflare Pages (مشروع `lamma`) بحساب Cloudflare المستقل للعبة (secrets: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID).
  - وبنفس الـ push ينبني الـ APK → Release باسم `apk-latest`. الويب والـ APK دائماً من نفس التعديل.
  - رقم النسخة: `appVersion` بـ `lib/core/version.dart` + أول 7 حروف من الـ commit (`--dart-define=BUILD`)، ويطلع أسفل الشاشة الرئيسية.
  - مفتاح التوقيع الثابت `ci/debug.keystore` (حتى التحديث ينزل فوق القديم).
- الكود:
  - `lib/core/loop.dart` حلقة الإطارات + الإيقاف المؤقت لكل لعبة.
  - `lib/ui/kit.dart` العد التنازلي، شاشة النتيجة، قائمة الإيقاف، الأزرار.
  - `lib/games/` كل لعبة بملف، وتنضاف لـ `registry.dart`.
  - الرسوم كلها بالكود (CustomPainter) بدون صور.
  - الأصوات والموسيقى تنولد بالكود: `dart run tools/gen_sfx.dart` → `assets/sfx/`، وتشتغل عبر `lib/core/sfx.dart` (Sfx + Music).
  - الأداء: الأشياء الثابتة (سطوح، خلفيات) تنرسم مرة وحدة كصورة (`toImageSync`)، وتجنّب `MaskFilter.blur` باللي ينرسم كل إطار.
- الخط: Tajawal للنصوص و Lalezar للعناوين (داخل assets/fonts).
- القادم: اللعب أونلاين بغرف وكود (Cloudflare Workers + Durable Objects)، ثم الواي فاي المحلي للأندرويد.
- قاعدة الرفع: التعديلات تترفع على `main` مباشرة، بس نجمّع كم تعديل ونرفع لمّن صاحب المشروع يگول (كل رفعة تبني ويب و APK).
