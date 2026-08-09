// service-worker.js
// Phase 1: caches the static app shell only, for faster repeat loads.
// Does NOT cache API responses — auth and data must always hit the network
// so RLS-protected data never comes from a stale cache. Offline data
// support (session notes, attendance) is a Phase 3 concern.

const CACHE_NAME = 'tutoros-shell-v1';
const SHELL_FILES = [
  '/index.html',
  '/manifest.json',
  '/app.css',
  '/supabase-client.js',
  '/auth.js',
  '/business.js',
  '/workspace.js',
  '/ui-helpers.js',
  '/router-guard.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Never cache Supabase API/auth calls.
  if (url.hostname.endsWith('supabase.co')) return;

  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
