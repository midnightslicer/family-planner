import { Controller } from "@hotwired/stimulus"

// The wall can't scroll, so if the board is taller than the screen (a big
// family, lots of places) shrink it to fit, keeping it full width. Runs
// again on resize and whenever a live refresh morphs the page.
export default class extends Controller {
  connect() {
    this.fit = this.fit.bind(this)
    window.addEventListener("resize", this.fit)
    document.addEventListener("turbo:morph", this.fit)
    requestAnimationFrame(this.fit)
  }

  disconnect() {
    window.removeEventListener("resize", this.fit)
    document.removeEventListener("turbo:morph", this.fit)
  }

  fit() {
    const board = this.element
    board.style.transform = ""
    board.style.width = ""
    if (board.scrollHeight <= window.innerHeight) return

    // The largest scale s at which the board, laid out (100 / s)% wide and
    // then shrunk by s, spans the screen exactly and fits its height.
    // Widening changes how the columns pack, so search rather than divide.
    const fits = (scale) => {
      board.style.width = `${100 / scale}%`
      return board.scrollHeight * scale <= window.innerHeight
    }
    let low = 0.3
    let high = 1
    for (let round = 0; round < 10; round++) {
      const mid = (low + high) / 2
      if (fits(mid)) low = mid
      else high = mid
    }
    fits(low)
    board.style.transform = `scale(${low})`
  }
}
