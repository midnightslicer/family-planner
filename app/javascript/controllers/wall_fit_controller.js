import { Controller } from "@hotwired/stimulus"

// The wall can't scroll, so this fits the board to the screen. The board is
// a band per place (name on the left, same-size tiles flowing right, kiosk.css),
// and two things decide how it fills the screen: how many tiles go across
// (--tiles, the same in every band so tiles line up down the board) and the
// scale. For each tile count it finds the largest scale that fits, never
// letting tiles get narrower than MIN_TILE, and keeps the best: so a small
// family is shown big, and a big one shrinks only as far as it must.
//
// Live updates should read as calm movement, not a reshuffle:
// - The layout is sticky: it only changes when the current one stops
//   fitting or another is clearly (STICKY) bigger, so a clock line ticking
//   over doesn't flip the board.
// - Changes animate (FLIP): before Turbo morphs the page or renders a
//   stream, every band and tile's position is noted by id; after the new
//   layout, each glides from where it was, and newcomers fade in.
//
// - No unfitted frame: a refresh morph would reset the board's inline style
//   (width, --tiles, scale) to the server's plain markup and paint it
//   squeezed for a frame, so the board keeps its style through morphs, and
//   re-fitting after a change runs before the browser paints.
//
// Runs on resize, after a morph, and when cards are added or replaced.
const MIN_TILE = 230 // px before scaling: narrower and tiles get cramped
const MAX_TILES = 8
const SCALES = [0.35, 1.5] // smallest and largest scale searched
const STICKY = 0.06 // another layout must be this much bigger to switch
const GLIDE = { duration: 700, easing: "cubic-bezier(0.22, 1, 0.36, 1)" }

export default class extends Controller {
  connect() {
    // After DOM changes: a microtask, so it lands before the next paint.
    this.refit = () => {
      if (this.pending) return
      this.pending = true
      queueMicrotask(() => {
        this.pending = false
        this.fit()
      })
    }
    // Resizes and loads can wait for the next frame.
    this.queue = () => {
      cancelAnimationFrame(this.frame)
      this.frame = requestAnimationFrame(() => this.fit())
    }
    this.keepStyle = (event) => {
      if (event.target === this.element && event.detail.attributeName === "style") event.preventDefault()
    }
    this.snapshot = () => { this.before ||= this.positions() }
    window.addEventListener("resize", this.queue)
    window.addEventListener("load", this.queue) // photos and fonts change sizes
    document.addEventListener("turbo:morph", this.refit)
    document.addEventListener("turbo:before-morph-attribute", this.keepStyle)
    document.addEventListener("turbo:before-render", this.snapshot)
    document.addEventListener("turbo:before-stream-render", this.snapshot)
    // Live card replacements arrive as turbo streams, without a morph.
    this.observer = new MutationObserver(this.refit)
    this.observer.observe(this.element, { childList: true, subtree: true })
    this.fit()
  }

  disconnect() {
    window.removeEventListener("resize", this.queue)
    window.removeEventListener("load", this.queue)
    document.removeEventListener("turbo:morph", this.refit)
    document.removeEventListener("turbo:before-morph-attribute", this.keepStyle)
    document.removeEventListener("turbo:before-render", this.snapshot)
    document.removeEventListener("turbo:before-stream-render", this.snapshot)
    this.observer.disconnect()
    cancelAnimationFrame(this.frame)
  }

  fit() {
    const board = this.element
    const bands = [...board.querySelectorAll(".wall-cards")]
    if (bands.length === 0) return
    board.style.transform = ""

    const most = Math.max(...bands.map((band) => band.children.length))
    const counts = Array.from({ length: Math.min(MAX_TILES, Math.max(most, 1)) }, (_, i) => i + 1)
    let best = null
    for (const tiles of counts) {
      const scale = this.largestScale(tiles, bands)
      if (scale && (!best || scale > best.scale + 0.005)) best = { tiles, scale }
    }
    best ||= { tiles: 1, scale: SCALES[0] } // nothing fits: smallest we go

    // Stay put unless the current layout no longer fits or another is
    // clearly bigger; and don't nudge the scale by a hair.
    const current = this.current
    if (current && counts.includes(current.tiles)) {
      const scale = this.largestScale(current.tiles, bands)
      if (scale && best.scale < scale * (1 + STICKY)) best = { tiles: current.tiles, scale }
      if (best.tiles === current.tiles && Math.abs(best.scale - current.scale) < current.scale * STICKY / 2 &&
          this.layout(current.tiles, current.scale, bands)) best = current
    }
    this.current = best

    this.layout(best.tiles, best.scale, bands)
    board.style.transform = `scale(${best.scale})`
    if (this.before) {
      this.glide(this.before, best.scale)
      this.before = null
    }
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

  // ---- Animating changes ----

  movers() {
    return [...this.element.querySelectorAll(".wall-place[id], .wall-cards > [id]")]
  }

  positions() {
    return new Map(this.movers().map((element) => [element.id, element.getBoundingClientRect()]))
  }

  // Each band and tile glides from where it was; newcomers fade in. A
  // tile's move is counted inside its band's, so it isn't moved twice.
  // Rects are screen pixels; transforms inside the board are in its own
  // (unscaled) pixels, hence `/ scale`.
  glide(before, scale) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
    const after = this.positions()
    const shift = (id) => {
      const from = before.get(id)
      const to = after.get(id)
      return from && to ? { x: from.left - to.left, y: from.top - to.top } : { x: 0, y: 0 }
    }
    for (const element of this.movers()) {
      const from = before.get(element.id)
      if (!from) {
        element.animate([{ opacity: 0 }, { opacity: 1 }], { ...GLIDE, duration: 500 })
        continue
      }
      const to = after.get(element.id)
      const own = shift(element.id)
      const band = element.matches(".wall-place") ? { x: 0, y: 0 } : shift(element.closest(".wall-place")?.id)
      const x = (own.x - band.x) / scale
      const y = (own.y - band.y) / scale
      const sx = element.matches(".wall-place") ? 1 : from.width / to.width
      const sy = element.matches(".wall-place") ? 1 : from.height / to.height
      if (Math.abs(x) < 1 && Math.abs(y) < 1 && Math.abs(sx - 1) < 0.01 && Math.abs(sy - 1) < 0.01) continue
      element.animate(
        [{ transformOrigin: "top left", transform: `translate(${x}px, ${y}px) scale(${sx}, ${sy})` },
         { transformOrigin: "top left", transform: "none" }],
        GLIDE
      )
    }
  }
}
