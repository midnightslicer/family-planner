import { Controller } from "@hotwired/stimulus"

// "What's new" (layouts/_changelog). Opens by itself when there's an update
// you haven't seen (auto), and from anything with data-changelog-open.
// Closing it any way at all (Got it, Escape, a tap outside) counts as seen:
// it posts once and stops opening by itself.
export default class extends Controller {
  static values = { auto: Boolean, url: String }

  connect() {
    // A live refresh morphs the page to the server's copy, where the dialog
    // isn't open: leave it alone while it is.
    this.keep = (event) => { if (event.target === this.element && this.element.open) event.preventDefault() }
    this.element.addEventListener("turbo:before-morph-element", this.keep)
    if (this.autoValue && !this.element.open) this.element.showModal()
  }

  disconnect() {
    this.element.removeEventListener("turbo:before-morph-element", this.keep)
  }

  openFrom(event) {
    if (!event.target.closest("[data-changelog-open]")) return
    event.preventDefault()
    if (!this.element.open) this.element.showModal()
  }

  // A tap on the backdrop lands on the dialog itself, outside its box.
  backdrop(event) {
    if (event.target !== this.element) return
    const box = this.element.getBoundingClientRect()
    const inside = event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom
    if (!inside) this.element.close()
  }

  closed() {
    if (!this.autoValue) return
    this.autoValue = false
    fetch(this.urlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" }
    }).catch((error) => console.warn("Couldn't save that you've seen what's new", error))
  }
}
