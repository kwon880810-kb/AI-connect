// 오프라인에서도 첫 화면이 열리도록 기본 파일을 캐시합니다.
// 파일을 고친 뒤 배포할 때는 VERSION 숫자를 올려 주세요.
const VERSION = "v4";
const CACHE = "winwin-connect-" + VERSION;
const FILES = ["./", "index.html", "login.html", "request.html", "projects.html", "directory.html", "supplier.html", "terms.html", "privacy.html", "css/style.css", "js/config.js", "js/sb.js", "vendor/supabase.js", "manifest.webmanifest", "icons/icon.svg", "icons/icon-192.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
// 네트워크 우선, 실패하면 캐시 (항상 최신 내용을 보여주기 위해)
self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET" || new URL(e.request.url).origin !== location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return res; })
      .catch(() => caches.match(e.request).then((r) => r || caches.match("index.html")))
  );
});
