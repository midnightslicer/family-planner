// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"

// Tell the server which time zone this browser is in, so "fed today" and
// times on screen follow the viewer's clock (ApplicationController#use_browser_time_zone).
try {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
  if (zone) document.cookie = `tz=${encodeURIComponent(zone)}; path=/; max-age=31536000; samesite=lax`
} catch {}
