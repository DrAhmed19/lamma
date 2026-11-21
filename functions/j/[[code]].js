// رابط الدعوة: lamma-dk0.pages.dev/j/CODE (و /j/ بدون غرفة = دعوة للمّة بس)
//
// - واتساب وغيره يقرون وسوم og ويطلعون بطاقة: شعار لمّة + اسم اللعبة + اسم صاحب الغرفة.
//   المعلومات تجي من سيرفر الغرف (/info/CODE).
// - الإنسان ينتقل للويب ويدخل الغرفة مباشرة (/?room=CODE)، وإذا الغرفة منتهية (/?room=CODE&gone=1).
// - أندرويد وعنده التطبيق: App Links تفتح التطبيق قبل ما توصل هنا (assetlinks.json ينحط بالـ CI).
//
// عنوان السيرفر ينحط بالـ CI بدل __SERVER__ (نفس عنوان --dart-define=SERVER).

const SERVER = "__SERVER__";

// نفس أسماء lib/games/registry.dart
const GAMES = {
  xo: "إكس أو",
  connect4: "أربعة في صف",
  tug: "شدّ الحبل",
  hockey: "الهوكي",
  pigeon: "الحمامة",
  reaction: "أسرع إصبع",
  quiz: "سؤال وجواب",
};

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

async function roomInfo(code) {
  if (!SERVER.startsWith("http")) return null;
  try {
    const r = await fetch(`${SERVER}/info/${code}`, { cf: { cacheTtl: 0 } });
    if (!r.ok) return null;
    return await r.json();
  } catch (_) {
    return null;
  }
}

export async function onRequestGet({ request, params }) {
  const origin = new URL(request.url).origin;
  const raw = Array.isArray(params.code) ? params.code[0] ?? "" : params.code ?? "";
  const code = /^[A-Za-z]{4}$/.test(raw) ? raw.toUpperCase() : null;

  let title = "تعال العب وياي بلمّة! 🎮";
  let desc = "ألعاب جماعية للأهل والأصدقاء: إكس أو، الحمامة، الهوكي، سؤال وجواب وغيرها.";
  let target = "/";

  if (code) {
    const info = await roomInfo(code);
    if (info && info.exists === false) {
      title = "انتهت هاي الغرفة";
      desc = "سوّي غرفة جديدة والعب ويا أصدقائك بلمّة.";
      target = `/?room=${code}&gone=1`;
    } else {
      const game = GAMES[info?.game] ?? "";
      const host = (info?.host ?? "").trim();
      title = game ? `تعال العب وياي ${game} بلمّة! 🎮` : "تعال العب وياي بلمّة! 🎮";
      desc = host ? `${host} يدعوك للعب · رمز الغرفة ${code}` : `رمز الغرفة ${code}`;
      target = `/?room=${code}`;
    }
  }

  const img = `${origin}/brand/og.png`;
  const html = `<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="لمّة">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(request.url)}">
<meta property="og:image" content="${esc(img)}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:locale" content="ar_IQ">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#090C18">
<meta http-equiv="refresh" content="0;url=${esc(target)}">
<style>body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#090C18;color:#fff;font-family:sans-serif}</style>
</head>
<body>
<a href="${esc(target)}" style="color:#C9B8FF">لمّة</a>
<script>location.replace(${JSON.stringify(target)});</script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      // البطاقة تتغيّر ويا حالة الغرفة
      "cache-control": "no-store",
    },
  });
}
