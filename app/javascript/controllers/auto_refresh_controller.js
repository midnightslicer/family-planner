import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Keeps a long-open board current. Live updates arrive over Action Cable;
// this also refreshes when the tab comes back into view (catching anything
// missed while the device slept) and, on the wall, every `interval` seconds
// as a safety net if the websocket quietly drops.
export default class extends Controller {
  static values = { interval: Number }

  connect() {
    this.onVisible = () => {
      if (document.visibilityState === "visible") this.refresh()
    }
    document.addEventListener("visibilitychange", this.onVisible)
    if (this.intervalValue > 0) {
      this.timer = setInterval(() => {
        if (document.visibilityState === "visible") this.refresh()
      }, this.intervalValue * 1000)
    }
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    clearInterval(this.timer)
  }

  refresh() {
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
