module WebAuthn
  # Decoder for the subset of CBOR (RFC 8949) that authenticators emit:
  # integers, byte/text strings, arrays, maps, tags and simple values.
  # Indefinite lengths and floats are rejected; nothing in WebAuthn uses them.
  module Cbor
    MAX_DEPTH = 16

    module_function

    def decode(bytes)
      value, offset = decode_prefix(bytes)
      raise Error, "trailing CBOR data" unless offset == bytes.bytesize

      value
    end

    # Decodes one item from the start of `bytes`, returning [value, bytes_read].
    # authenticatorData ends with a COSE key and optional extensions, so the
    # caller needs to know where the key stops.
    def decode_prefix(bytes)
      read(bytes.b, 0, 0)
    end

    def read(buffer, position, depth)
      raise Error, "CBOR nested too deeply" if depth > MAX_DEPTH

      initial = buffer.getbyte(position) or raise Error, "truncated CBOR"
      position += 1
      major = initial >> 5
      info = initial & 0x1f
      raise Error, "unsupported CBOR value" if major == 7 && info > 23

      argument, position = read_argument(buffer, position, info)
      # Each string byte, array item or map entry needs at least one byte, so
      # a count larger than what is left is malformed (and would over-allocate).
      raise Error, "truncated CBOR" if major.between?(2, 5) && argument > buffer.bytesize - position

      case major
      when 0 then [argument, position]
      when 1 then [-1 - argument, position]
      when 2, 3
        string = buffer.byteslice(position, argument)
        string.force_encoding(Encoding::UTF_8) if major == 3
        [string, position + argument]
      when 4
        items = Array.new(argument) do
          item, position = read(buffer, position, depth + 1)
          item
        end
        [items, position]
      when 5
        map = {}
        argument.times do
          key, position = read(buffer, position, depth + 1)
          map[key], position = read(buffer, position, depth + 1)
        end
        [map, position]
      when 6 then read(buffer, position, depth + 1) # tag: keep the tagged value
      when 7
        case argument
        when 20 then [false, position]
        when 21 then [true, position]
        when 22, 23 then [nil, position]
        else raise Error, "unsupported CBOR simple value"
        end
      end
    end

    def read_argument(buffer, position, info)
      width = { 24 => 1, 25 => 2, 26 => 4, 27 => 8 }[info]
      return [info, position] if info < 24
      raise Error, "unsupported CBOR length" unless width
      raise Error, "truncated CBOR" if position + width > buffer.bytesize

      value = buffer.byteslice(position, width).bytes.inject(0) { |acc, byte| (acc << 8) | byte }
      [value, position + width]
    end
  end
end
