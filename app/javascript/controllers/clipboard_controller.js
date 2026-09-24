import { Controller } from "@hotwired/stimulus"

// Copy-to-clipboard for invite and wall links. Falls back to selecting the
// text where the clipboard API isn't available (plain-http LAN installs).
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const text = this.sourceTarget.value ?? this.sourceTarget.textContent
    try {
      await navigator.clipboard.writeText(text)
      this.flash("Copied")
    } catch {
      this.sourceTarget.select?.()
      this.flash("Press Ctrl+C / ⌘C")
    }
  }

  flash(label) {
    const original = this.buttonTarget.dataset.label || this.buttonTarget.textContent
    this.buttonTarget.dataset.label = original
    this.buttonTarget.textContent = label
    clearTimeout(this.timer)
    this.timer = setTimeout(() => (this.buttonTarget.textContent = original), 2000)
  }
}
