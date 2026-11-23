import { Controller } from "@hotwired/stimulus"
import { pushKey, pushSupported, isIos, currentSubscription } from "../lib/push"

// The "Get notifications on your phone" banner (shared/_notifications_banner).
// Rendered hidden; shown only where it can help: push is set up on the
// server, this device isn't getting notifications yet, the person hasn't
// blocked them or said "No thanks". It links to the Notifications page and
// never asks for permission itself.
const DISMISSED = "push-nudge-dismissed"

export default class extends Controller {
  async connect() {
    if (await this.wanted()) this.element.hidden = false
  }

  async wanted() {
    if (!pushKey() || localStorage.getItem(DISMISSED)) return false
    if (!pushSupported()) return isIos() // iPhone in Safari: install first
    if (Notification.permission === "denied") return false
    return !(Notification.permission === "granted" && await currentSubscription())
  }

  dismiss() {
    localStorage.setItem(DISMISSED, "1")
    this.element.remove()
  }
}
