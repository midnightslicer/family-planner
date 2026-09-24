# Minimal QR code encoder (byte mode, error correction level M) that renders
# an inline SVG. It exists so the two-factor setup page can show a scannable
# code without a gem or a third-party image service; the otpauth:// URI holds
# the TOTP secret and must never leave the server.
#
# The layout follows ISO/IEC 18004: function patterns, Reed-Solomon ECC over
# GF(256), interleaved blocks, the zigzag data placement and the eight masks.
class QrCode
  # Level M, indexed by version (index 0 unused).
  ECC_CODEWORDS_PER_BLOCK = [
    nil, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
    26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28
  ].freeze
  ECC_BLOCKS = [
    nil, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
    17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49
  ].freeze
  FORMAT_ECC_BITS = 0 # level M
  QUIET_ZONE = 4

  attr_reader :version, :size, :mask

  def initialize(text, mask: nil)
    data = text.to_s.b.bytes
    @version = (1..40).find { |ver| data_bit_capacity(ver) >= segment_bits(ver, data.length) } or
      raise ArgumentError, "text too long for a QR code"
    @size = @version * 4 + 17
    @modules = Array.new(@size) { Array.new(@size, false) }
    @function = Array.new(@size) { Array.new(@size, false) }

    draw_function_patterns
    draw_codewords(add_ecc_and_interleave(encode_data(data)))
    @mask = mask || best_mask
    apply_mask(@mask)
    draw_format_bits(@mask)
  end

  def dark?(x, y)
    @modules[y][x]
  end

  # One path of unit squares; colours come from CSS so it follows the theme
  # tokens while keeping the dark-on-light contrast scanners need.
  def to_svg(css_class: "qr-code", label: "QR code")
    extent = @size + QUIET_ZONE * 2
    path = +""
    @size.times do |y|
      @size.times do |x|
        path << "M#{x + QUIET_ZONE} #{y + QUIET_ZONE}h1v1h-1z" if dark?(x, y)
      end
    end
    %(<svg xmlns="http://www.w3.org/2000/svg" class="#{css_class}" viewBox="0 0 #{extent} #{extent}" ) +
      %(role="img" aria-label="#{label}" shape-rendering="crispEdges">) +
      %(<rect class="qr-light" width="#{extent}" height="#{extent}"/><path class="qr-dark" d="#{path}"/></svg>)
  end

  private

  # ---- Data encoding ----

  def char_count_bits(ver)
    ver <= 9 ? 8 : 16
  end

  def segment_bits(ver, length)
    4 + char_count_bits(ver) + length * 8
  end

  def raw_data_modules(ver)
    result = (16 * ver + 128) * ver + 64
    if ver >= 2
      num_align = ver / 7 + 2
      result -= (25 * num_align - 10) * num_align - 55
      result -= 36 if ver >= 7
    end
    result
  end

  def data_codewords(ver)
    raw_data_modules(ver) / 8 - ECC_CODEWORDS_PER_BLOCK[ver] * ECC_BLOCKS[ver]
  end

  def data_bit_capacity(ver)
    data_codewords(ver) * 8
  end

  def encode_data(data)
    bits = +"0100" # byte mode
    bits << data.length.to_s(2).rjust(char_count_bits(@version), "0")
    data.each { |byte| bits << byte.to_s(2).rjust(8, "0") }

    capacity = data_bit_capacity(@version)
    bits << "0" * [4, capacity - bits.length].min
    bits << "0" * ((8 - bits.length % 8) % 8)
    codewords = bits.scan(/.{8}/).map { |byte| byte.to_i(2) }
    pad = [0xEC, 0x11]
    index = 0
    while codewords.length < data_codewords(@version)
      codewords << pad[index % 2]
      index += 1
    end
    codewords
  end

  # ---- Error correction ----

  def add_ecc_and_interleave(data)
    num_blocks = ECC_BLOCKS[@version]
    ecc_len = ECC_CODEWORDS_PER_BLOCK[@version]
    raw_codewords = raw_data_modules(@version) / 8
    num_short_blocks = num_blocks - raw_codewords % num_blocks
    short_block_len = raw_codewords / num_blocks
    divisor = reed_solomon_divisor(ecc_len)

    offset = 0
    blocks = Array.new(num_blocks) do |i|
      length = short_block_len - ecc_len + (i < num_short_blocks ? 0 : 1)
      block = data[offset, length]
      offset += length
      ecc = reed_solomon_remainder(block, divisor)
      block += [0] if i < num_short_blocks
      block + ecc
    end

    result = []
    blocks[0].length.times do |i|
      blocks.each_with_index do |block, j|
        # Skip the padding byte that short blocks carry to line up columns.
        result << block[i] if i != short_block_len - ecc_len || j >= num_short_blocks
      end
    end
    result
  end

  def reed_solomon_divisor(degree)
    result = Array.new(degree - 1, 0) + [1]
    root = 1
    degree.times do
      degree.times do |j|
        result[j] = gf_multiply(result[j], root)
        result[j] ^= result[j + 1] if j + 1 < result.length
      end
      root = gf_multiply(root, 0x02)
    end
    result
  end

  def reed_solomon_remainder(data, divisor)
    result = Array.new(divisor.length, 0)
    data.each do |byte|
      factor = byte ^ result.shift
      result << 0
      divisor.each_with_index { |coef, i| result[i] ^= gf_multiply(coef, factor) }
    end
    result
  end

  def gf_multiply(x, y)
    z = 0
    7.downto(0) do |i|
      z = (z << 1) ^ ((z >> 7) * 0x11D)
      z ^= ((y >> i) & 1) * x
    end
    z
  end

  # ---- Function patterns ----

  def set_function(x, y, dark)
    @modules[y][x] = dark
    @function[y][x] = true
  end

  def draw_function_patterns
    @size.times do |i|
      set_function(6, i, i.even?)
      set_function(i, 6, i.even?)
    end

    draw_finder(3, 3)
    draw_finder(@size - 4, 3)
    draw_finder(3, @size - 4)

    positions = alignment_positions
    last = positions.length - 1
    positions.each_with_index do |px, i|
      positions.each_with_index do |py, j|
        next if (i.zero? && j.zero?) || (i.zero? && j == last) || (i == last && j.zero?)

        draw_alignment(px, py)
      end
    end

    draw_format_bits(0) # reserve the area; real bits are drawn after masking
    draw_version_bits
  end

  def draw_finder(cx, cy)
    (-4..4).each do |dy|
      (-4..4).each do |dx|
        x = cx + dx
        y = cy + dy
        next unless x.between?(0, @size - 1) && y.between?(0, @size - 1)

        distance = [dx.abs, dy.abs].max
        set_function(x, y, distance != 2 && distance != 4)
      end
    end
  end

  def draw_alignment(cx, cy)
    (-2..2).each do |dy|
      (-2..2).each do |dx|
        set_function(cx + dx, cy + dy, [dx.abs, dy.abs].max != 1)
      end
    end
  end

  def alignment_positions
    return [] if @version == 1

    num_align = @version / 7 + 2
    step = (@version * 8 + num_align * 3 + 5) / (num_align * 4 - 4) * 2
    result = []
    position = @size - 7
    (num_align - 1).times do
      result.unshift(position)
      position -= step
    end
    result.unshift(6)
  end

  def draw_format_bits(mask)
    data = (FORMAT_ECC_BITS << 3) | mask
    remainder = data
    10.times { remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537) }
    bits = ((data << 10) | remainder) ^ 0x5412
    bit = ->(i) { ((bits >> i) & 1) == 1 }

    (0..5).each { |i| set_function(8, i, bit.(i)) }
    set_function(8, 7, bit.(6))
    set_function(8, 8, bit.(7))
    set_function(7, 8, bit.(8))
    (9..14).each { |i| set_function(14 - i, 8, bit.(i)) }

    (0..7).each { |i| set_function(@size - 1 - i, 8, bit.(i)) }
    (8..14).each { |i| set_function(8, @size - 15 + i, bit.(i)) }
    set_function(8, @size - 8, true) # the always-dark module
  end

  def draw_version_bits
    return if @version < 7

    remainder = @version
    12.times { remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25) }
    bits = (@version << 12) | remainder
    18.times do |i|
      dark = ((bits >> i) & 1) == 1
      a = @size - 11 + i % 3
      b = i / 3
      set_function(a, b, dark)
      set_function(b, a, dark)
    end
  end

  # ---- Data placement and masking ----

  def draw_codewords(codewords)
    total_bits = codewords.length * 8
    i = 0
    right = @size - 1
    while right >= 1
      right = 5 if right == 6 # skip the vertical timing column
      upward = ((right + 1) & 2).zero?
      @size.times do |vert|
        y = upward ? @size - 1 - vert : vert
        2.times do |j|
          x = right - j
          next if @function[y][x] || i >= total_bits

          @modules[y][x] = ((codewords[i >> 3] >> (7 - (i & 7))) & 1) == 1
          i += 1
        end
      end
      right -= 2
    end
  end

  def mask_bit?(mask, x, y)
    case mask
    when 0 then (x + y).even?
    when 1 then y.even?
    when 2 then (x % 3).zero?
    when 3 then ((x + y) % 3).zero?
    when 4 then ((x / 3) + (y / 2)).even?
    when 5 then (x * y % 2 + x * y % 3).zero?
    when 6 then ((x * y % 2) + (x * y % 3)).even?
    when 7 then (((x + y) % 2) + (x * y % 3)).even?
    end
  end

  def apply_mask(mask)
    @size.times do |y|
      @size.times do |x|
        @modules[y][x] ^= true if !@function[y][x] && mask_bit?(mask, x, y)
      end
    end
  end

  def best_mask
    (0..7).min_by do |mask|
      apply_mask(mask)
      draw_format_bits(mask)
      score = penalty_score
      apply_mask(mask) # XOR again to undo
      score
    end
  end

  FINDER_LIKE = [
    [true, false, true, true, true, false, true, false, false, false, false],
    [false, false, false, false, true, false, true, true, true, false, true]
  ].freeze

  def penalty_score
    rows = @modules
    columns = @modules.transpose
    score = 0

    (rows + columns).each do |line|
      line.chunk_while { |a, b| a == b }.each do |run|
        score += run.length - 2 if run.length >= 5
      end
      (0..line.length - 11).each do |start|
        score += 40 if FINDER_LIKE.include?(line[start, 11])
      end
    end

    (@size - 1).times do |y|
      (@size - 1).times do |x|
        color = rows[y][x]
        score += 3 if color == rows[y][x + 1] && color == rows[y + 1][x] && color == rows[y + 1][x + 1]
      end
    end

    total = @size * @size
    dark = rows.sum { |row| row.count(true) }
    k = ((dark * 20 - total * 10).abs + total - 1) / total - 1
    score + k * 10
  end
end
