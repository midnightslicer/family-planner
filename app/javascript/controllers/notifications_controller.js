import { Controller } from "@hotwired/stimulus"

// Web notifications banner: shows an explicit "Enable notifications" button
// (never auto-prompts). The button requests permission and dismisses the
// banner once granted or denied.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    if (!("Notification" in window)) {
      this.element.remove()
      return
    }
    if (Notification.permission !== "default") {
      this.element.remove()
    }
  }

  async enable() {
    await Notification.requestPermission()
    this.element.remove()
  }
}