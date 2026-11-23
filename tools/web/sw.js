// service worker لمّة: «الشبكة أولاً» حتى كل رفعة جديدة تطلع فوراً (ما نعلّق نسخة قديمة).
// المخزّن بس احتياط لمّن ماكو إنترنت. نسخة الكاش تتغير ويا رقم البناء.
const CACHE = 'lamma-__BUILD__';
const CORE = ['./', 'index.html', 'manifest.webmanifest', 'favicon.png', 'icons/Icon-192.png', 'brand/logo.png'];

self.addEventListener('install', (e) => {
  self.skipWaiting(); // النسخة الجديدة تشتغل مباشرة
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(CORE)).catch(() => {}));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => k.startsWith('lamma-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return; // السيرفر والخطوط الخارجية: بدون تدخل
  e.respondWith(
    fetch(req, { cache: 'no-cache' })
      .then((res) => {
        if (res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() => caches.match(req).then((r) => r || (req.mode === 'navigate' ? caches.match('index.html') : undefined))),
  );
});
