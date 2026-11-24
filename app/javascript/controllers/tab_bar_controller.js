import { Controller } from "@hotwired/stimulus"

// The phone's tab bar (layouts/_tab_bar): hidden while you scroll down the
// page, back as soon as you scroll up or reach the bottom. The state lives
// on <html>, which Turbo never swaps, so a live morph refresh doesn't pop
// the bar back mid-scroll; a new page starts with it showing.
const HIDDEN = "tab-bar-hidden"
const THRESHOLD = 8 // px of scrolling before it reacts, so a jiggle doesn't flicker it
const TOP = 48 // near the top it always shows

export default class extends Controller {
  connect() {
    this.lastY = window.scrollY
    if (this.lastY < TOP) document.documentElement.classList.remove(HIDDEN)
    this.onScroll = () => { this.frame ||= requestAnimationFrame(() => this.update()) }
    window.addEventListener("scroll", this.onScroll, { passive: true })
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    cancelAnimationFrame(this.frame)
    this.frame = null
  }

  update() {
    this.frame = null
    const y = Math.max(0, window.scrollY)
    const delta = y - this.lastY
    if (Math.abs(delta) < THRESHOLD) return

    const atBottom = window.innerHeight + y >= document.documentElement.scrollHeight - 2
    document.documentElement.classList.toggle(HIDDEN, delta > 0 && y > TOP && !atBottom)
    this.lastY = y
  }
}
