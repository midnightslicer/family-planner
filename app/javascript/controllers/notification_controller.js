import { Controller } from "@hotwired/stimulus"

// One broadcast notification (see shared/_notification): shown as a browser
// notification if the person allowed them, then removed from the page.
export default class extends Controller {
  static values = { title: String, body: String, tag: String }

  connect() {
    if ("Notification" in window && Notification.permission === "granted") {
      new Notification(this.titleValue, { body: this.bodyValue, tag: this.tagValue })
    }
    this.element.remove()
  }
}
