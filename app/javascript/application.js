// Entry point for the build script in your package.json
import { Turbo } from "@hotwired/turbo-rails"
import "./controllers"

// On a visit to a page seen before, Turbo paints its cached copy at once
// (the preview: phones never prefetch, so this is what makes a tap feel
// instant) and then the fresh page. Replacing the preview would play every
// entrance animation a second time, a jitter; morphing the fresh page into
// it keeps the elements, so they animate once and only what changed updates.
let previewShown = false
document.addEventListener("turbo:visit", () => { previewShown = false })
document.addEventListener("turbo:before-render", (event) => {
  const isPreview = document.documentElement.hasAttribute("data-turbo-preview")
  if (!isPreview && previewShown && event.detail.renderMethod === "replace") {
    event.detail.render = (currentBody, newBody) => Turbo.morphBodyElements(currentBody, newBody)
  }
  previewShown = isPreview
})

// Tell the server which time zone this browser is in, so "fed today" and
// times on screen follow the viewer's clock (ApplicationController#use_browser_time_zone).
try {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
  if (zone) document.cookie = `tz=${encodeURIComponent(zone)}; path=/; max-age=31536000; samesite=lax`
} catch {}

// And whether it's in dark mode, so the installed app's manifest can match
// its system bars to the page (PwaController#manifest).
const darkMode = window.matchMedia("(prefers-color-scheme: dark)")
const rememberScheme = () => {
  document.cookie = `scheme=${darkMode.matches ? "dark" : "light"}; path=/; max-age=31536000; samesite=lax`
}
rememberScheme()
darkMode.addEventListener("change", rememberScheme)

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
