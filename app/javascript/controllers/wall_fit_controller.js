import { Controller } from "@hotwired/stimulus"

// The wall can't scroll, so this fits the board to the screen. The board is
// a band per place (name on the left, same-size tiles flowing right, kiosk.css),
// and two things decide how it fills the screen: how many tiles go across
// (--tiles, the same in every band so tiles line up down the board) and the
// scale. For each tile count it finds the largest scale that fits, never
// letting tiles get narrower than MIN_TILE, and keeps the best: so a small
// family is shown big, and a big one shrinks only as far as it must.
//
// Runs again on resize, after a live refresh morphs the page (which resets
// these inline styles), and when a card is added or replaced.
const MIN_TILE = 230 // px before scaling: narrower and tiles get cramped
const MAX_TILES = 8
const SCALES = [0.35, 1.5] // smallest and largest scale searched

export default class extends Controller {
  connect() {
    this.queue = () => {
      cancelAnimationFrame(this.frame)
      this.frame = requestAnimationFrame(() => this.fit())
    }
    window.addEventListener("resize", this.queue)
    window.addEventListener("load", this.queue) // photos and fonts change sizes
    document.addEventListener("turbo:morph", this.queue)
    // Live card replacements arrive as turbo streams, without a morph.
    this.observer = new MutationObserver(this.queue)
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.queue()
  }

  disconnect() {
    window.removeEventListener("resize", this.queue)
    window.removeEventListener("load", this.queue)
    document.removeEventListener("turbo:morph", this.queue)
    this.observer.disconnect()
    cancelAnimationFrame(this.frame)
  }

  fit() {
    const board = this.element
    const bands = [...board.querySelectorAll(".wall-cards")]
    if (bands.length === 0) return
    board.style.transform = ""

    const most = Math.max(...bands.map((band) => band.children.length))
    let best = null
    for (let tiles = 1; tiles <= Math.min(MAX_TILES, Math.max(most, 1)); tiles++) {
      const scale = this.largestScale(tiles, bands)
      if (scale && (!best || scale > best.scale + 0.005)) best = { tiles, scale }
    }
    best ||= { tiles: 1, scale: SCALES[0] } // nothing fits: smallest we go
    this.layout(best.tiles, best.scale, bands)
    board.style.transform = `scale(${best.scale})`
  }

  // The largest scale at which the board fits with this many tiles across,
  // or null if it doesn't fit even at the smallest.
  largestScale(tiles, bands) {
    const fits = (scale) => this.layout(tiles, scale, bands)
    let [low, high] = SCALES
    if (!fits(low)) return null
    if (fits(high)) return high
    for (let round = 0; round < 9; round++) {
      const mid = (low + high) / 2
      if (fits(mid)) low = mid
      else high = mid
    }
    return low
  }

  // Lays the board out (unscaled) for a scale and says whether it fits.
  layout(tiles, scale, bands) {
    const board = this.element
    board.style.width = `${window.innerWidth / scale}px`
    board.style.setProperty("--tiles", tiles)
    const tile = bands[0].firstElementChild
    if (tile && tile.offsetWidth < MIN_TILE) return false
    return board.scrollHeight <= window.innerHeight / scale
  }
}
