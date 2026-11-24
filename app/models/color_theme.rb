# The app's colour tokens for one person, built from the colour they picked
# for their profile. The accent (links, primary buttons, focus rings, icons)
# is their colour, darkened or lightened just enough to read on each theme,
# and the neutrals (page background, sunken panels, borders) carry a faint
# tint of its hue, so the whole app feels like theirs without getting loud.
#
# Works in OKLCH, where lightness is perceptual: keeping a colour's hue and
# chroma while moving only L keeps it recognisably "their" colour. Every
# value comes out as a hex the layout prints into a <style> token block
# (ThemeHelper#theme_tokens_tag), overriding the defaults in application.css.
class ColorTheme
  HEX = /\A#?(\h{6})\z/

  # Below this chroma a colour is a grey: its hue means nothing, so the
  # neutrals keep the app's default cool tint instead.
  GREY = 0.03
  DEFAULT_HUE = 262.0

  # WCAG contrast the accent keeps against the page and its own button text.
  MIN_CONTRAST = 4.6

  def self.for(hex)
    match = HEX.match(hex.to_s.strip)
    new(match[1]) if match
  end

  def initialize(hex)
    @l, @c, @h = Oklch.from_hex(hex)
    @tint_hue = @c < GREY ? DEFAULT_HUE : @h
  end

  def light
    @light ||= begin
      bg = tint(0.972, 0.010)
      accent = readable(on: bg, from: [@l, 0.62].min, step: -0.01)
      {
        "--bg" => bg,
        "--surface-sunken" => tint(0.983, 0.007),
        "--border" => tint(0.926, 0.012),
        "--border-strong" => tint(0.872, 0.016),
        "--accent" => accent,
        "--accent-hover" => shade(accent, -0.06),
        "--accent-soft" => Oklch.to_hex(0.957, [@c * 0.3, 0.035].min, @h),
        "--accent-fg" => "#ffffff"
      }
    end
  end

  def dark
    @dark ||= begin
      bg = tint(0.172, 0.012)
      accent = readable(on: bg, from: [@l, 0.74].max, step: 0.01)
      {
        "--bg" => bg,
        "--surface" => tint(0.215, 0.015),
        "--surface-sunken" => tint(0.245, 0.017),
        "--border" => tint(0.298, 0.019),
        "--border-strong" => tint(0.372, 0.022),
        "--accent" => accent,
        "--accent-hover" => shade(accent, 0.05),
        "--accent-soft" => Oklch.rgba(accent, 0.16),
        "--accent-fg" => bg
      }
    end
  end

  # The installed app's title bar matches --surface.
  def surface(scheme) = scheme == :dark ? dark["--surface"] : "#ffffff"

  def self.contrast(hex_a, hex_b)
    a, b = [hex_a, hex_b].map { |hex| Oklch.luminance(hex) }.minmax
    (b + 0.05) / (a + 0.05)
  end

  private

  def tint(lightness, chroma)
    strength = @c < GREY ? 0.6 : 1.0
    Oklch.to_hex(lightness, chroma * strength, @tint_hue)
  end

  # Their colour at the nearest lightness that reads on `on` (and, in the
  # light theme, under white button text: that's the same test, since the
  # page is nearly white).
  def readable(on:, from:, step:)
    lightness = from
    hex = Oklch.to_hex(lightness, @c, @h)
    while self.class.contrast(hex, on) < MIN_CONTRAST && lightness.between?(0.05, 0.98)
      lightness += step
      hex = Oklch.to_hex(lightness, @c, @h)
    end
    hex
  end

  def shade(hex, delta)
    l, c, h = Oklch.from_hex(hex.delete("#"))
    Oklch.to_hex(l + delta, c, h)
  end

  # sRGB <-> OKLab/OKLCH (Björn Ottosson's matrices), with out-of-gamut
  # colours brought back by lowering chroma, never by clipping channels
  # (which would shift the hue).
  module Oklch
    module_function

    def from_hex(hex)
      r, g, b = hex.scan(/../).map { |pair| linear(pair.to_i(16) / 255.0) }
      l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
      m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
      s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
      lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
      a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
      bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
      [lightness, Math.hypot(a, bb), Math.atan2(bb, a) * 180 / Math::PI % 360]
    end

    def to_hex(lightness, chroma, hue)
      lightness = lightness.clamp(0.0, 1.0)
      rgb = rgb(lightness, chroma, hue)
      unless in_gamut?(rgb)
        low = 0.0
        high = chroma
        12.times do
          mid = (low + high) / 2
          in_gamut?(rgb(lightness, mid, hue)) ? low = mid : high = mid
        end
        rgb = rgb(lightness, low, hue)
      end
      "#" + rgb.map { |channel| format("%02x", (gamma(channel.clamp(0.0, 1.0)) * 255).round) }.join
    end

    def rgba(hex, alpha)
      r, g, b = hex.delete("#").scan(/../).map { |pair| pair.to_i(16) }
      "rgba(#{r}, #{g}, #{b}, #{alpha})"
    end

    def luminance(hex)
      r, g, b = hex.delete("#").scan(/../).map { |pair| linear(pair.to_i(16) / 255.0) }
      0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    def rgb(lightness, chroma, hue)
      rad = hue * Math::PI / 180
      a = chroma * Math.cos(rad)
      b = chroma * Math.sin(rad)
      l = (lightness + 0.3963377774 * a + 0.2158037573 * b)**3
      m = (lightness - 0.1055613458 * a - 0.0638541728 * b)**3
      s = (lightness - 0.0894841775 * a - 1.2914855480 * b)**3
      [
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
      ]
    end

    def in_gamut?(rgb) = rgb.all? { |channel| channel.between?(-0.0001, 1.0001) }

    def linear(channel)
      channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end

    def gamma(channel)
      channel <= 0.0031308 ? channel * 12.92 : 1.055 * channel**(1 / 2.4) - 0.055
    end
  end
end
