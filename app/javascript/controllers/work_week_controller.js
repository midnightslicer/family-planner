import { Controller } from "@hotwired/stimulus"

// Work schedule: "Copy Monday to Tuesday–Friday", the usual week in one
// tap. Rows are Monday first.
export default class extends Controller {
  static targets = ["day", "on", "from", "until", "place", "tools"]

  connect() {
    this.toolsTarget.hidden = false
  }

  copyMonday() {
    for (let i = 1; i <= 4; i++) {
      this.onTargets[i].checked = this.onTargets[0].checked
      this.fromTargets[i].value = this.fromTargets[0].value
      this.untilTargets[i].value = this.untilTargets[0].value
      this.placeTargets[i].value = this.placeTargets[0].value
    }
  }
}
