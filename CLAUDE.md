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
- الأونلاين (غرف بكود): السيرفر هو اللي يدير اللعبة ويحسم، والتطبيقات بس تعرض وتدز الحركات.
  - قواعد كل لعبة بـ Dart صافي (بدون Flutter) بـ `lib/logic/` (تورث `GameModel`)، وتنضاف لـ `models.dart`.
    نفس الكود يشتغل بالتطبيق (نفس الجهاز) وينبني JavaScript للسيرفر: `dart compile js -O2 -o server/src/logic.js server/dart/main.dart`.
  - السيرفر `server/` (Worker + Durable Object لكل غرفة). محلياً: `cd server && npx wrangler dev`. CI يرفعه وينطي عنوانه للويب والـ APK (`--dart-define=SERVER`).
  - بالتطبيق: `lib/net/room.dart` الاتصال، `lib/net/session.dart` (LocalSession / OnlineSession) الواجهة الوحدة للعبة، `lib/ui/online.dart` الغرفة.
  - اللعبة تقرا من `session.model` وترسل `session.input(...)`، والمؤثرات من `session.takeEvents()`.
  - اللي طلع، حتى صاحب الغرفة، اللعبة تكمل بدونه ويرجع يلحق. بلعبة لاعبين: إذا غاب دقيقة الثاني يفوز.
  - صارن على الأساس: إكس أو، أربعة بالصف، شد الحبل. الباقي (الحمامة، الهوكي، أسرع إصبع) بعدهن.
- القادم: نقل باقي الألعاب للأساس، ثم الواي فاي المحلي للأندرويد، ثم اللعب ويا الغرباء.
- قاعدة الرفع: التعديلات تترفع على `main` مباشرة، بس نجمّع كم تعديل ونرفع لمّن صاحب المشروع يگول (كل رفعة تبني ويب و APK).
