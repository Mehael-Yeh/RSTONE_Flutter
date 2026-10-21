'use strict';

// This inventory contains application build resources, never official data.
const VERSION = __RSTONE_BUILD_HASH__;
const FILES = __RSTONE_RESOURCE_LIST__;
const SCOPE = self.registration.scope;
const PREFIX = 'rstone-shell:' + SCOPE + ':';
const CACHE = PREFIX + VERSION;
const allowed = new Set(Object.keys(FILES));

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    try {
      for (const [file, expected] of Object.entries(FILES)) {
        const request = new Request(new URL(file, SCOPE), {cache: 'reload', credentials: 'omit'});
        const response = await fetch(request);
        if (!response.ok) throw new Error('Offline shell resource unavailable');
        const bytes = await response.clone().arrayBuffer();
        const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)))
          .map(value => value.toString(16).padStart(2, '0')).join('');
        if (hash !== expected) throw new Error('Offline shell resource integrity mismatch');
        await cache.put(request, response);
      }
      await self.skipWaiting();
    } catch (error) {
      await caches.delete(CACHE);
      throw error;
    }
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(PREFIX) && name !== CACHE) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || !request.url.startsWith(SCOPE)) return;
  const url = new URL(request.url);
  const base = new URL(SCOPE);
  const path = decodeURIComponent(url.pathname.slice(base.pathname.length)) || 'index.html';
  if (!allowed.has(path)) return;
  // The worker only serves one completely cached shell generation. Data
  // manifests and objects are outside this inventory and use Data Protocol v1.
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    return await cache.match(new URL(path, SCOPE)) || fetch(request);
  })());
});
