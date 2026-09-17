// Network-only worker. Offline data synchronization is not implemented.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('workbox-precache') || key.startsWith('flutter-')) {
        await caches.delete(key);
      }
    }
    await self.clients.claim();
  })());
});
