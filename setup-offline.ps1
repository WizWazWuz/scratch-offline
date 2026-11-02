
$ErrorActionPreference = "Stop"

Write-Host "Preparing Scratch offline files..."

# Collect the files needed by Scratch
$files = Get-ChildItem -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\.git\\' -and
    $_.Extension -ne ".map" -and
    $_.Name -notlike "*.LICENSE.txt" -and
    (
        $_.FullName -match '\\(chunks|static)\\' -or
        $_.Name -in @(
            "index.html",
            "gui.js",
            "extension-worker.js"
        ) -or
        $_.Extension -eq ".hex"
    )
}

$paths = @($files | ForEach-Object {
    $_.FullName.Substring((Get-Location).Path.Length + 1).Replace('\','/')
})

$json = ConvertTo-Json -InputObject $paths -Compress
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText("$PWD\precache.json", $json, $utf8)

# Create the offline service worker
$sw = @'
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
'@

[IO.File]::WriteAllText("$PWD\sw.js", $sw, $utf8)

# Create the web app manifest
$manifest = @'
{
  "name": "Scratch Offline",
  "short_name": "Scratch",
  "start_url": "./",
  "scope": "./",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#4c97ff"
}
'@

[IO.File]::WriteAllText(
    "$PWD\manifest.webmanifest",
    $manifest,
    $utf8
)

# Update the Scratch homepage
$html = @'
<!doctype html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="google" value="notranslate">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Scratch">
<meta name="theme-color" content="#4c97ff">
<link rel="manifest" href="./manifest.webmanifest">
<link rel="shortcut icon" href="static/favicon.ico">
<title>Scratch Offline</title>
<script>
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js")
    .then(() => console.log("Scratch offline service worker installed"))
    .catch(error => console.error("Offline setup failed:", error));
}
</script>
<script defer="defer" src="gui.js"></script>
</head>
<body></body>
</html>
'@

[IO.File]::WriteAllText("$PWD\index.html", $html, $utf8)

Write-Host ""
Write-Host "Offline files created successfully."
Write-Host "Files prepared: $($paths.Count)"
Write-Host "Next: upload the files to GitHub."
