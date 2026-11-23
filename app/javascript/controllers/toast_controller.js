import { Controller } from "@hotwired/stimulus"

// One in-page notification (shared/_notification), appended to the
// #notifications stack by a broadcast while the app is open. Goes away by
// itself after a while (not while hovered or focused), or on "Dismiss".
// The system notification for the same update comes from the service worker.
const KEEP = 4 // at most this many on screen; the oldest go first

export default class extends Controller {
  static values = { delay: { type: Number, default: 8000 } }

  connect() {
    const stack = this.element.parentElement
    while (stack && stack.children.length > KEEP) stack.firstElementChild.remove()
    this.start()
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
