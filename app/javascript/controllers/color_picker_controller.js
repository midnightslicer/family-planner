import { Controller } from "@hotwired/stimulus"

// Keeps the palette and the custom hex box from contradicting each other:
// picking a swatch clears the box (a filled box wins on the server), and a
// valid hex in the box unticks the swatches. Either way, anything in the same
// form marked [data-color-preview] is recoloured live.
const HEX = /^#?[0-9a-f]{6}$/i

export default class extends Controller {
  static targets = ["swatch", "custom"]

  pick(event) {
    if (this.hasCustomTarget) this.customTarget.value = ""
    this.preview(event.target.value)
  }

  type() {
    const value = this.customTarget.value.trim()
    if (!HEX.test(value)) return

    this.swatchTargets.forEach((swatch) => (swatch.checked = false))
    this.preview(value.startsWith("#") ? value : `#${value}`)
  }

  preview(hex) {
    const form = this.element.closest("form")
    if (!form) return

    form.querySelectorAll("[data-color-preview]").forEach((el) => {
      el.style.setProperty("--user-color", hex)
      el.style.setProperty("--user-fg", contrast(hex))
    })
  }
}

// Same rule as ApplicationHelper#contrast_color.
function contrast(hex) {
  const n = parseInt(hex.slice(1), 16)
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255]
  const luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
  return luminance > 0.55 ? "#111827" : "#ffffff"
}
