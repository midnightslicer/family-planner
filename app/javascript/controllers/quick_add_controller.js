import { Controller } from "@hotwired/stimulus"

// The schedule's quick add. The form is data-turbo-permanent, so page
// refreshes leave it alone, and the server answers with a turbo stream that
// replaces the lists around it, so the box never loses focus (on a phone the
// keyboard stays up for the next item). The title clears as soon as the
// request is on its way, ready to type into; if the add fails it comes back.
export default class extends Controller {
  static targets = ["title", "more"]

  sent() {
    this.pending = this.titleTarget.value
    this.titleTarget.value = ""
  }

  added(event) {
    if (!event.detail.success) {
      if (!this.titleTarget.value) this.titleTarget.value = this.pending || ""
      return
    }
    // Typed something new while the last one was saving: keep it.
    const typed = this.titleTarget.value
    this.element.reset()
    this.titleTarget.value = typed
    this.moreTarget.open = false
    this.element.dispatchEvent(new Event("quick-add:reset", { bubbles: true }))
    this.titleTarget.focus()
  }
}
