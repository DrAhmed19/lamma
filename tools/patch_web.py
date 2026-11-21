"""يعدّل index.html و manifest.json للويب: عربي، داكن، شاشة تحميل، وإضافة للشاشة الرئيسية."""
import json, re, pathlib

idx = pathlib.Path("web/index.html")
h = idx.read_text(encoding="utf-8")
h = re.sub(r'<html[^>]*>', '<html lang="ar" dir="rtl">', h, count=1)
h = re.sub(r'<title>.*?</title>', '<title>لمّة - ألعاب جماعية</title>', h, flags=re.S)
h = re.sub(r'<meta name="description"[^>]*>', '<meta name="description" content="لمّة: ألعاب جماعية للأهل والأصدقاء">', h)
h = re.sub(r'<meta name="apple-mobile-web-app-title"[^>]*>', '<meta name="apple-mobile-web-app-title" content="لمّة">', h)
h = re.sub(r'<link rel="apple-touch-icon"[^>]*>', '<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">', h)
h = h.replace('content="black"', 'content="black-translucent"')
h = re.sub(r'<meta name="viewport"[^>]*>\s*', '', h)
head_extra = '''
  <meta name="theme-color" content="#090C18">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
  <style>
    html, body { margin:0; height:100%; background:#090C18; overscroll-behavior:none; touch-action:none; }
    #lamma-loading { position:fixed; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:18px;
      background: radial-gradient(circle at 50% 40%, #1d1950 0%, #090C18 65%); transition: opacity .35s ease; z-index:1; }
    #lamma-loading img { width:112px; height:112px; border-radius:28px; animation: lp 1.4s ease-in-out infinite; box-shadow:0 10px 40px rgba(139,108,255,.35); }
    #lamma-loading div { width:120px; height:4px; border-radius:4px; background:rgba(255,255,255,.1); overflow:hidden; }
    #lamma-loading div::after { content:""; display:block; width:40%; height:100%; background:#8B6CFF; border-radius:4px; animation: lb 1.1s ease-in-out infinite; }
    @keyframes lp { 50% { transform: scale(1.06); } }
    @keyframes lb { 0% { transform: translateX(260%); } 100% { transform: translateX(-120%); } }
  </style>
'''
dpr_cap = '''
  <script>
    // دقة الرسم: الآيفون/الآيباد يرسم بـ 2x أو 3x = بكسلات هواية كل إطار = تقطيع.
    // نحدّها لـ 1.5 (الفرق بالشكل ما يبين تقريباً، والرسم أخف بكثير)
    (function () {
      try {
        var real = window.devicePixelRatio || 1;
        var cap = Math.min(real, 1.5);
        if (cap < real) Object.defineProperty(window, 'devicePixelRatio', { get: function () { return cap; }, configurable: true });
      } catch (e) {}
    })();
  </script>
'''
h = h.replace('<head>', '<head>' + dpr_cap, 1)
h = h.replace('</head>', head_extra + '</head>', 1)
body_extra = '''
  <div id="lamma-loading"><img src="brand/logo.png" alt="لمّة"><div></div></div>
  <script>
    window.addEventListener('flutter-first-frame', function () {
      var l = document.getElementById('lamma-loading');
      if (l) { l.style.opacity = '0'; setTimeout(function () { l.remove(); }, 400); }
    });
  </script>
'''
h = re.sub(r'(<body[^>]*>)', r'\1' + body_extra, h, count=1)
idx.write_text(h, encoding="utf-8")

# flutter_bootstrap مخصص: ?r=ck يشغّل محرك CanvasKit بدل Skwasm (للمقارنة بالآيفون)
pathlib.Path("web/flutter_bootstrap.js").write_text("""{{flutter_js}}
{{flutter_build_config}}
(function () {
  var r = new URLSearchParams(location.search).get('r');
  try { if (r) localStorage.setItem('lamma_r', r); else r = localStorage.getItem('lamma_r'); } catch (e) {}
  var cfg = {};
  if (r === 'ck') cfg.renderer = 'canvaskit';
  if (r === 'sk') cfg.renderer = 'skwasm';
  _flutter.loader.load({ config: cfg });
})();
""", encoding="utf-8")

mp = pathlib.Path("web/manifest.json")
m = json.loads(mp.read_text(encoding="utf-8"))
m.update({
    "name": "لمّة - ألعاب جماعية",
    "short_name": "لمّة",
    "description": "ألعاب جماعية للأهل والأصدقاء",
    "background_color": "#090C18",
    "theme_color": "#090C18",
    "orientation": "portrait",
    "display": "standalone",
    "lang": "ar",
    "dir": "rtl",
})
mp.write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding="utf-8")
print("web patched")
