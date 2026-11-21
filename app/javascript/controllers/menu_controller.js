import { Controller } from "@hotwired/stimulus"

// Closes a <details> dropdown (the nav's account menu) when you click
// outside it or press Escape; <details> handles opening by itself.
export default class extends Controller {
  outside(event) {
    if (this.element.open && !this.element.contains(event.target)) this.element.open = false
  }

  close() {
    if (!this.element.open) return
    this.element.open = false
    this.element.querySelector("summary")?.focus()
  }
}
