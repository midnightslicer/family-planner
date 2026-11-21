import { Controller } from "@hotwired/stimulus"

// A small burst of confetti from the button that finished a task. Purely
// decorative: the pieces live on <body> (the card gets replaced by the turbo
// stream mid-animation) and remove themselves. Skipped for reduced motion.
const PIECES = 14
const COLORS = ["--status-completed", "--status-planned", "--status-in_progress", "--accent"]

export default class extends Controller {
  burst() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const rect = this.element.getBoundingClientRect()
    const x = rect.left + rect.width / 2
    const y = rect.top + rect.height / 2

    for (let i = 0; i < PIECES; i++) {
      const piece = document.createElement("span")
      piece.className = "confetti"
      piece.setAttribute("aria-hidden", "true")
      const angle = (Math.PI * 2 * i) / PIECES + Math.random() * 0.4
      const distance = 40 + Math.random() * 40
      piece.style.left = `${x}px`
      piece.style.top = `${y}px`
      piece.style.setProperty("--dx", `${Math.cos(angle) * distance}px`)
      piece.style.setProperty("--dy", `${Math.sin(angle) * distance - 20}px`)
      piece.style.setProperty("--spin", `${Math.round(Math.random() * 540 - 270)}deg`)
      piece.style.background = `var(${COLORS[i % COLORS.length]})`
      piece.addEventListener("animationend", () => piece.remove(), { once: true })
      document.body.appendChild(piece)
    }
  }
}
