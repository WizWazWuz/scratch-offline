const CACHE_NAME = "scratch-offline-v1";

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const base = self.registration.scope;
    const response = await fetch(new URL("precache.json", base));

    if (!response.ok) {
      throw new Error("Could not load precache.json");
    }

    const files = await response.json();
    const cache = await caches.open(CACHE_NAME);

    // Download in small batches to avoid overwhelming Safari
    for (let i = 0; i < files.length; i += 8) {
      const batch = files.slice(i, i + 8);

      await Promise.all(batch.map(async path => {
        const url = new URL(path, base);
        const result = await fetch(url, {cache: "reload"});

        if (!result.ok) {
          throw new Error("Failed to cache: " + path);
        }

        await cache.put(url, result);
      }));

      console.log("Cached " + Math.min(i + 8, files.length) +
                  " of " + files.length + " files");
    }

    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();

    await Promise.all(
      keys.filter(key => key.startsWith("scratch-offline-") &&
                         key !== CACHE_NAME)
          .map(key => caches.delete(key))
    );

    await self.clients.claim();
  })());
});

self.addEventListener("fetch", event => {
  const request = event.request;
  const url = new URL(request.url);

  if (request.method !== "GET" ||
      url.origin !== self.location.origin) {
    return;
  }

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);

    const cached = await cache.match(request, {
      ignoreSearch: true
    });

    if (cached) return cached;

    if (request.mode === "navigate") {
      const homepage = await cache.match(
        new URL("index.html", self.registration.scope)
      );

      if (homepage) return homepage;
    }

    return fetch(request);
  })());
});