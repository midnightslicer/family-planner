import { Controller } from "@hotwired/stimulus"
import { currentSubscription, showLocalNotification } from "../lib/push"

// One in-page notification (shared/_notification), appended to the
// #notifications stack by a broadcast while the app is open. Goes away by
// itself after a while (not while hovered or focused), or on "Dismiss".
// The system notification for the same update comes from the service worker,
// on a device that gets pushes. On one that can't (Brave on a computer), a
// tab in the background shows it itself when the server says it may buzz
// (`alert`); every open tab uses the same tag, so it shows once.
const KEEP = 4 // at most this many on screen; the oldest go first

export default class extends Controller {
  static values = { delay: { type: Number, default: 8000 }, alert: Boolean, title: String, body: String, path: String }

  connect() {
    const stack = this.element.parentElement
    while (stack && stack.children.length > KEEP) stack.firstElementChild.remove()
    this.start()
    this.alertIfAway()
  }

  async alertIfAway() {
    if (!this.alertValue || (document.visibilityState === "visible" && document.hasFocus())) return
    try {
      if (await currentSubscription()) return // the push brings it
      await showLocalNotification(this.titleValue, { body: this.bodyValue, tag: this.element.dataset.tag, path: this.pathValue })
    } catch (error) {
      console.warn("Couldn't show a notification", error)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  start() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.dismiss(), this.delayValue)
  }

  hold() {
    clearTimeout(this.timer)
  }

  dismiss() {
    clearTimeout(this.timer)
    this.element.remove()
  }
}
