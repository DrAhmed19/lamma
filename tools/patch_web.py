"""يعدّل index.html و manifest.json للويب: عربي، داكن، شاشة تحميل، وإضافة للشاشة الرئيسية."""
import json, re, pathlib

idx = pathlib.Path("web/index.html")
h = idx.read_text(encoding="utf-8")
h = re.sub(r'<html[^>]*>', '<html lang="ar" dir="rtl">', h, count=1)
h = re.sub(r'<title>.*?</title>', '<title>لمّة - ألعاب جماعية</title>', h, flags=re.S)
h = re.sub(r'<meta name="description"[^>]*>', '<meta name="description" content="لمّة: ألعاب جماعية للأهل والأصدقاء">', h)
h = re.sub(r'<meta name="apple-mobile-web-app-title"[^>]*>', '<meta name="apple-mobile-web-app-title" content="لمّة">', h)
h = re.sub(r'<link rel="apple-touch-icon"[^>]*>', '<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">', h)
h = re.sub(r'<meta name="viewport"[^>]*>\s*', '', h)
head_extra = '''
  <meta name="theme-color" content="#E7F2FC">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="default">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
  <style>
    html, body { margin:0; height:100%; background:#E7F2FC; overscroll-behavior:none; touch-action:none; }
    #lamma-loading { position:fixed; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:18px;
      background: radial-gradient(circle at 70% 0%, #CFE8FF 0%, #E7F2FC 60%); transition: opacity .35s ease; z-index:1; }
    #lamma-loading img { width:112px; height:112px; border-radius:28px; animation: lp 1.4s ease-in-out infinite; box-shadow:0 6px 0 #D2E5F5, 0 14px 30px rgba(30,50,90,.15); }
    #lamma-loading div { width:120px; height:4px; border-radius:4px; background:#D2E5F5; overflow:hidden; }
    #lamma-loading div::after { content:""; display:block; width:40%; height:100%; background:#2E9BF0; border-radius:4px; animation: lb 1.1s ease-in-out infinite; }
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
    // تثبيت التطبيق (PWA): Dart يقرا هاي عبر lammaPwa
    window.lammaPwa = {
      prompt: null,
      standalone: function () { return window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true; },
      kind: function () {
        var ua = navigator.userAgent || '';
        if (/iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) return 'ios';
        if (this.prompt) return 'prompt';
        if (/Firefox/.test(ua) && /Android/.test(ua)) return 'menu';
        if (/Android/.test(ua) && !/Chrome|SamsungBrowser|Edg/.test(ua)) return 'menu';
        return 'none';
      },
      install: function () {
        var p = this.prompt; if (!p) return;
        this.prompt = null; p.prompt();
      }
    };
    window.addEventListener('beforeinstallprompt', function (e) { e.preventDefault(); window.lammaPwa.prompt = e; });
    window.addEventListener('appinstalled', function () { window.lammaPwa.prompt = null; });
    if ('serviceWorker' in navigator && window.isSecureContext && !/[?&]lan=1/.test(location.search)) {
      window.addEventListener('load', function () {
        navigator.serviceWorker.register('sw.js', { updateViaCache: 'none' }).then(function (r) { r.update(); }).catch(function () {});
      });
    }
  </script>
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
  try {
    if (r === 'auto') { localStorage.removeItem('lamma_r'); r = null; }
    else if (r) localStorage.setItem('lamma_r', r);
    else r = localStorage.getItem('lamma_r');
  } catch (e) {}
  var cfg = {};
  // آيفون/آيباد/سفاري: محرك skwasm بطيء كلش (جربناه: 2-7 إطار بالثانية، وCanvasKit 50+)،
  // فنستخدم CanvasKit إلهم دائماً. باقي المتصفحات تبقى على skwasm (أسرع بكروم).
  var ua = navigator.userAgent || '';
  var apple = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1) ||
    (/Safari/.test(ua) && !/Chrome|Chromium|Edg|Android/.test(ua));
  if (!r && apple) r = 'ck';
  if (r === 'ck') cfg.renderer = 'canvaskit';
  if (r === 'sk') cfg.renderer = 'skwasm';
  _flutter.loader.load({ config: cfg });
})();
""", encoding="utf-8")

icons = [
    {"src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any"},
    {"src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any"},
    {"src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable"},
    {"src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
]
m = {
    "id": "./",
    "name": "لمّة - ألعاب جماعية",
    "short_name": "لمّة",
    "description": "ألعاب جماعية للأهل والأصدقاء",
    "start_url": "./",
    "scope": "./",
    "display": "standalone",
    "orientation": "portrait",
    "background_color": "#E7F2FC",
    "theme_color": "#E7F2FC",
    "lang": "ar",
    "dir": "rtl",
    "icons": icons,
}
pathlib.Path("web/manifest.webmanifest").write_text(json.dumps(m, ensure_ascii=False, indent=2), encoding="utf-8")
pathlib.Path("web/manifest.json").unlink(missing_ok=True)
h = idx.read_text(encoding="utf-8")
h = re.sub(r'<link rel="manifest"[^>]*>', '<link rel="manifest" href="manifest.webmanifest">', h)
if 'rel="manifest"' not in h:
    h = h.replace('</head>', '  <link rel="manifest" href="manifest.webmanifest">\n</head>', 1)
idx.write_text(h, encoding="utf-8")

# service worker: نسخة الكاش برقم البناء
import os
sw = pathlib.Path("tools/web/sw.js").read_text(encoding="utf-8").replace("__BUILD__", os.environ.get("BUILD", "dev"))
pathlib.Path("web/sw.js").write_text(sw, encoding="utf-8")
print("web patched")
