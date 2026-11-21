import { Controller } from "@hotwired/stimulus"

// Tile pickers (pick pets, pick a place): "All" / "None" shortcuts, and the
// submit button counts what's picked ("Feed 2 pets"), so it's clear what
// will happen before it does. Details (feeding notes) for pets that aren't
// picked are hidden once anything is picked. Without JS the checkboxes
// still work and every note shows.
export default class extends Controller {
  static targets = ["option", "submit", "shortcuts", "detail"]
  static values = { verb: String, noun: { type: String, default: "pet" } }

  connect() {
    if (this.hasShortcutsTarget) this.shortcutsTarget.hidden = false
    this.update()
  }

  all() {
    this.optionTargets.forEach((box) => (box.checked = true))
    this.update()
  }

  none() {
    this.optionTargets.forEach((box) => (box.checked = false))
    this.update()
  }

  update() {
    const picked = this.optionTargets.filter((box) => box.checked).map((box) => box.value)
    this.detailTargets.forEach((detail) => {
      detail.hidden = picked.length > 0 && !picked.includes(detail.dataset.petId)
    })

    if (!this.hasSubmitTarget || !this.verbValue) return
    const count = picked.length
    const label = this.submitTarget.querySelector("span") || this.submitTarget
    label.textContent = count
      ? `${this.verbValue} ${count} ${this.nounValue}${count === 1 ? "" : "s"}`
      : `${this.verbValue}…`
    this.submitTarget.disabled = count === 0
  }
}
