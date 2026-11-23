// Entry point for the build script in your package.json
import { Turbo } from "@hotwired/turbo-rails"
import "./controllers"

// Tell the server which time zone this browser is in, so "fed today" and
// times on screen follow the viewer's clock (ApplicationController#use_browser_time_zone).
try {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
  if (zone) document.cookie = `tz=${encodeURIComponent(zone)}; path=/; max-age=31536000; samesite=lax`
} catch {}

// The service worker (PwaController), shared by the app and the installable
// wall. Only pages that link a manifest register it. Needs a secure
// context: https, or http://localhost while developing.
if ("serviceWorker" in navigator && window.isSecureContext && document.querySelector('link[rel="manifest"]')) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js", { scope: "/" }).catch((error) => {
      console.warn("Service worker registration failed", error)
    })
  })

  // A tapped notification, when the worker couldn't navigate this window
  // itself (see notificationclick in the worker).
  navigator.serviceWorker.addEventListener("message", (event) => {
    if (event.data?.type !== "visit") return
    const url = new URL(event.data.url, window.location.origin)
    if (url.origin === window.location.origin) Turbo.visit(url.href)
  })
}
