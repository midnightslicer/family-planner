require "test_helper"

class QrCodeTest < ActiveSupport::TestCase
  test "reed-solomon matches the worked HELLO WORLD 1-M example" do
    data = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17]
    qr = QrCode.new("x")
    divisor = qr.send(:reed_solomon_divisor, 10)
    assert_equal [196, 35, 39, 119, 235, 215, 231, 226, 93, 23], qr.send(:reed_solomon_remainder, data, divisor)
  end

  test "picks the smallest version that fits" do
    assert_equal 1, QrCode.new("a" * 14).version
    assert_equal 2, QrCode.new("a" * 15).version
    assert_equal 7, QrCode.new("a" * 122).version
  end

  test "draws finder patterns in three corners" do
    qr = QrCode.new("hello")
    [[0, 0], [qr.size - 7, 0], [0, qr.size - 7]].each do |x0, y0|
      assert qr.dark?(x0, y0)
      assert qr.dark?(x0 + 6, y0 + 6)
      assert_not qr.dark?(x0 + 1, y0 + 1)
      assert qr.dark?(x0 + 3, y0 + 3)
    end
    assert qr.dark?(8, qr.size - 8), "the fixed dark module"
  end

  test "renders an svg with a quiet zone" do
    svg = QrCode.new("otpauth://totp/x?secret=ABC").to_svg(label: "Scan me")
    assert svg.start_with?("<svg")
    assert_includes svg, %(aria-label="Scan me")
    assert_includes svg, "M4 4h1v1h-1z", "top-left finder module sits inside the 4-module margin"
  end

  test "rejects text beyond version 40" do
    assert_raises(ArgumentError) { QrCode.new("a" * 3000) }
  end
end
