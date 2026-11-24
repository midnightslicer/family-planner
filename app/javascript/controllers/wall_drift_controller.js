import { Controller } from "@hotwired/stimulus"
import { hexToOklab, oklch } from "../lib/oklch"

// Keeps the wall from burning in. A wall tablet shows the same board all
// day, so nothing on it may stay put: the whole page slowly drifts, far too
// slowly to watch but enough that no pixel holds one value for long.
//
// - Colour: the background, cards and borders are tinted with one family
//   member's profile colour at a time, gliding to the next every 20 minutes.
// - Tone: about every hour the board switches between dark and light in a
//   quick fade (TONE_FADE), text and cards together, because in between,
//   on mid-grey cards, neither light nor dark text reads. Within a tone it
//   only breathes a little, always staying where its text reads well. At
//   night (21:00–07:00 on the tablet's clock) it stays dark so it doesn't
//   light up the room.
// - Position: the board orbits a few pixels, so every edge and line of
//   text wanders, and two soft glows wander across the background.
//
// Everything is a function of the clock, so a reload picks up exactly where
// it was. Values go on <html> (`--drift-*`, `data-wall-tone`), which Turbo's
// morphing refreshes never touch; kiosk.css reads them, and CSS transitions
// as long as the tick make each step continuous.
const TICK = 10 * 1000
const MINUTE = 60 * 1000
const TONE_PERIOD = 120 * MINUTE // an hour dark, an hour light
const TONE_FADE = 3000 // ms: the switch, fast enough never to sit unreadable
const BREATHE = 17 * MINUTE // the slow lightness swing within a tone
const COLOUR_HOLD = 20 * MINUTE // per member colour, the last quarter a glide
const NIGHT_FROM = 21 * 60
const NIGHT_UNTIL = 7 * 60

const lerp = (from, to, t) => from + (to - from) * t
const smooth = (t) => {
  t = Math.min(1, Math.max(0, t))
  return t * t * (3 - 2 * t)
}
const wave = (now, period, phase = 0) => Math.sin((2 * Math.PI * now) / period + phase)

export default class extends Controller {
  static values = { colors: Array }

  connect() {
    this.colours = this.colorsValue.map(hexToOklab).filter(Boolean)
    if (this.colours.length === 0) this.colours = [hexToOklab("#6366f1")]
    this.root = document.documentElement
    this.themeMeta = document.querySelector('meta[name="theme-color"]')

    // ?speed=10 on the wall's URL plays the drift ten times faster, to
    // watch it work. Clock time runs fast from now, so it starts where the
    // real drift is; ticks and transitions shorten to match.
    const speed = Number(new URL(window.location.href).searchParams.get("speed"))
    this.speed = speed >= 1 ? Math.min(speed, 100) : 1
    this.started = Date.now()
    this.root.style.setProperty("--drift-tick", `${TICK / this.speed}ms`)

    this.apply()
    // Transitions only after the first paint, so opening the wall doesn't fade in.
    requestAnimationFrame(() => requestAnimationFrame(() => this.root.classList.add("wall-drift")))
    this.timer = setInterval(() => this.apply(), TICK / this.speed)
  }

  now() {
    const real = Date.now()
    return this.started + (real - this.started) * this.speed
  }

  disconnect() {
    clearInterval(this.timer)
    this.root.classList.remove("wall-drift")
    delete this.root.dataset.wallTone
    for (const name of [...this.root.style]) {
      if (name.startsWith("--drift-")) this.root.style.removeProperty(name)
    }
  }

  apply(now = this.now()) {
    const tone = this.tone(now)
    const light = tone === "light" ? 1 : 0
    // Within a tone, a slow swing of lightness (0–1) that keeps pixels
    // changing but never leaves the range where that tone's text reads.
    const b = 0.5 + 0.5 * wave(now, BREATHE)
    const { C, h, next } = this.colour(now)
    // How much of the family colour shows: none for a grey, all of it from
    // a properly saturated colour on.
    const strength = Math.min(1, C / 0.12)

    // Dark cards 0.19–0.26 and light 0.93–0.985 (OKLCH L): body and muted
    // text both clear 4.5:1 on them throughout.
    const surfaceL = light ? lerp(0.985, 0.93, b) : lerp(0.19, 0.26, b)
    const bgL = light ? lerp(0.955, 0.9, b) : lerp(0.15, 0.2, b)

    const props = {
      "--drift-bg": oklch(bgL, lerp(0.03, 0.02, light) * strength, h),
      "--drift-surface": oklch(surfaceL, lerp(0.028, 0.008, light) * strength, h),
      "--drift-surface-sunken": oklch(light ? surfaceL - 0.03 : surfaceL + 0.04, lerp(0.03, 0.012, light) * strength, h),
      "--drift-accent-soft": oklch(light ? 0.93 : 0.32, Math.min(C, 0.15) * 0.4, h),
      "--drift-border": oklch(light ? surfaceL - 0.09 : surfaceL + 0.085, 0.03 * strength, h),
      "--drift-border-strong": oklch(light ? surfaceL - 0.15 : surfaceL + 0.165, 0.035 * strength, h),
      "--drift-accent": oklch(tone === "light" ? 0.5 : 0.8, Math.min(C, 0.15), h),
      "--drift-glow": oklch(lerp(bgL + 0.09, bgL - 0.02, light), lerp(0.09, 0.07, light) * strength, h, 0.6),
      "--drift-glow-2": oklch(lerp(bgL + 0.08, bgL - 0.02, light), lerp(0.08, 0.06, light) * Math.min(1, next.C / 0.12), next.h, 0.45),
      "--drift-glow-x": `${(25 + 18 * wave(now, 53 * MINUTE)).toFixed(2)}%`,
      "--drift-glow-y": `${(22 + 14 * wave(now, 41 * MINUTE, 1)).toFixed(2)}%`,
      "--drift-glow-2-x": `${(76 + 16 * wave(now, 47 * MINUTE, 2)).toFixed(2)}%`,
      "--drift-glow-2-y": `${(80 + 12 * wave(now, 59 * MINUTE, 3)).toFixed(2)}%`,
      "--drift-x": `${(8 * wave(now, 37 * MINUTE)).toFixed(2)}px`,
      "--drift-y": `${(6 * wave(now, 23 * MINUTE, 1)).toFixed(2)}px`
    }
    props["--drift-accent-fg"] = tone === "light" ? "#ffffff" : oklch(0.16, 0.02, h)

    // A tone switch fades quickly, everything at once; other ticks glide
    // over the whole tick so they join into one slow change.
    const switching = this.lastTone && this.lastTone !== tone
    this.lastTone = tone
    props["--drift-tick"] = `${switching ? TONE_FADE : TICK / this.speed}ms`

    for (const [name, value] of Object.entries(props)) this.root.style.setProperty(name, value)
    this.root.dataset.wallTone = tone
    this.themeMeta?.setAttribute("content", props["--drift-bg"])
  }

  // The first half of each period dark, the second light; dark all night.
  tone(now) {
    const lightHalf = now % TONE_PERIOD >= TONE_PERIOD / 2
    return lightHalf && this.daylight(new Date(now)) === 1 ? "light" : "dark"
  }

  // 1 by day, 0 by night, with ten-minute ramps so dusk is a fade too.
  daylight(date) {
    const minutes = date.getHours() * 60 + date.getMinutes() + date.getSeconds() / 60
    if (minutes < NIGHT_UNTIL || minutes >= NIGHT_FROM + 10) return 0
    return Math.min(smooth((minutes - NIGHT_UNTIL) / 10), 1 - smooth((minutes - NIGHT_FROM) / 10))
  }

  // The current member's colour, gliding to the next. Mixed in OKLab: a
  // glide between far-apart hues softens on the way rather than sweeping
  // through every hue in between.
  colour(now) {
    const step = Math.floor(now / COLOUR_HOLD)
    const into = (now % COLOUR_HOLD) / COLOUR_HOLD
    const at = (n) => this.colours[((n % this.colours.length) + this.colours.length) % this.colours.length]
    const from = at(step)
    const to = at(step + 1)
    const t = smooth((into - 0.75) / 0.25)
    const a = lerp(from.a, to.a, t)
    const b = lerp(from.b, to.b, t)
    const polar = (x, y) => ({ C: Math.hypot(x, y), h: ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360 })
    return { ...polar(a, b), next: polar(to.a, to.b) }
  }
}
