import { Controller } from "@hotwired/stimulus"
import { syncSubscription } from "../lib/push"

// On every page of the app (layout): keeps this device's push subscription
// known to the server without ever prompting. See lib/push.js.
export default class extends Controller {
  static values = { url: String }

  connect() {
    syncSubscription(this.urlValue)
  }
}
