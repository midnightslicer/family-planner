// sRGB <-> OKLab / OKLCH (Björn Ottosson's matrices), the same maths as
// ColorTheme::Oklch on the server. OKLCH lightness is perceptual, so moving
// only L keeps a colour recognisably itself. Out-of-gamut colours come back
// by lowering chroma, never by clipping channels (which shifts the hue).

const linear = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
const gamma = (c) => (c <= 0.0031308 ? c * 12.92 : 1.055 * c ** (1 / 2.4) - 0.055)

export function hexToOklab(hex) {
  const value = /^#?([0-9a-f]{6})$/i.exec(hex.trim())
  if (!value) return null
  const [r, g, b] = value[1].match(/../g).map((pair) => linear(parseInt(pair, 16) / 255))
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  return {
    L: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
  }
}

function rgb(L, C, h) {
  const rad = (h * Math.PI) / 180
  const a = C * Math.cos(rad)
  const b = C * Math.sin(rad)
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
  ]
}

const inGamut = (channels) => channels.every((c) => c >= -0.0001 && c <= 1.0001)

// [r, g, b] 0–255 for an OKLCH colour, chroma reduced until it fits sRGB.
export function oklchToRgb(L, C, h) {
  L = Math.min(1, Math.max(0, L))
  let channels = rgb(L, C, h)
  if (!inGamut(channels)) {
    let low = 0
    let high = C
    for (let i = 0; i < 12; i++) {
      const mid = (low + high) / 2
      if (inGamut(rgb(L, mid, h))) low = mid
      else high = mid
    }
    channels = rgb(L, low, h)
  }
  return channels.map((c) => Math.round(gamma(Math.min(1, Math.max(0, c))) * 255))
}

export function oklch(L, C, h, alpha = 1) {
  const [r, g, b] = oklchToRgb(L, C, h)
  if (alpha < 1) return `rgba(${r}, ${g}, ${b}, ${alpha})`
  return `#${[r, g, b].map((c) => c.toString(16).padStart(2, "0")).join("")}`
}
