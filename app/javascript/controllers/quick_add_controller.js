import { Controller } from "@hotwired/stimulus"

// The schedule's quick add: after a successful add, clear the form, fold
// the time fields away and put the cursor back, ready for the next thing.
// (The page itself refreshes by morphing, which leaves a focused field
// alone, so clearing has to happen here.)
export default class extends Controller {
  static targets = ["title", "more"]

  added(event) {
    if (!event.detail.success) return
    this.element.reset()
    this.moreTarget.open = false
    this.titleTarget.focus()
  }
}
