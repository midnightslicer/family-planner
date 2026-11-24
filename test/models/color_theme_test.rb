require "test_helper"

class ColorThemeTest < ActiveSupport::TestCase
  test "every palette colour gives an accent that reads on both themes" do
    (User::PALETTE + %w[#ffffff #000000 #ffff00 #00ff00 #808080]).each do |colour|
      theme = ColorTheme.for(colour)
      light = theme.light
      dark = theme.dark

      assert_operator ColorTheme.contrast(light["--accent"], light["--bg"]), :>=, 4.5, "#{colour} light accent on the page"
      assert_operator ColorTheme.contrast(light["--accent"], light["--accent-fg"]), :>=, 4.5, "#{colour} button text"
      assert_operator ColorTheme.contrast(dark["--accent"], dark["--surface"]), :>=, 4.5, "#{colour} dark accent on a card"
      assert_operator ColorTheme.contrast(dark["--accent"], dark["--accent-fg"]), :>=, 4.5, "#{colour} dark button text"
    end
  end

  test "the accent keeps the person's hue" do
    hue = ->(hex) { ColorTheme::Oklch.from_hex(hex.delete("#"))[2] }
    %w[#ec4899 #22c55e #3b82f6 #f97316].each do |colour|
      theme = ColorTheme.for(colour)
      [theme.light["--accent"], theme.dark["--accent"]].each do |accent|
        drift = (hue.(accent) - hue.(colour)).abs
        assert_operator [drift, 360 - drift].min, :<, 6, "#{colour} -> #{accent}"
      end
    end
  end

  test "neutrals stay neutral: a faint tint, not a colour" do
    theme = ColorTheme.for("#ef4444")
    _, chroma, = ColorTheme::Oklch.from_hex(theme.light["--bg"].delete("#"))
    assert_operator chroma, :<, 0.02
  end

  test "anything that isn't a hex colour gives no theme" do
    assert_nil ColorTheme.for(nil)
    assert_nil ColorTheme.for("red")
    assert_nil ColorTheme.for("#12345")
    assert_nil ColorTheme.for("#123456;}body{display:none")
  end

  test "hex round trip" do
    %w[#6366f1 #0f766e #a8a29e #ffffff #000000].each do |colour|
      assert_equal colour, ColorTheme::Oklch.to_hex(*ColorTheme::Oklch.from_hex(colour.delete("#")))
    end
  end
end
