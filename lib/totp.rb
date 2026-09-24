require "openssl"
require "securerandom"

# RFC 6238 time-based one-time passwords: the rolling six-digit codes that
# authenticator apps (1Password, Google Authenticator, iOS Passwords, Aegis...)
# show. Built on OpenSSL's HMAC so no extra gem is needed.
module Totp
  DIGITS = 6
  PERIOD = 30
  # Accept the code from one step either side of now to absorb clock skew.
  DRIFT_STEPS = 1
  BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze

  module_function

  # 160 random bits, the size RFC 4226 recommends, as base32 for the apps.
  def random_secret
    base32_encode(SecureRandom.random_bytes(20))
  end

  def time_step(time = Time.now)
    time.to_i / PERIOD
  end

  def code_at(secret, step)
    hmac = OpenSSL::HMAC.digest("SHA1", base32_decode(secret), [step].pack("Q>"))
    offset = hmac.getbyte(-1) & 0x0f
    value = hmac.byteslice(offset, 4).unpack1("N") & 0x7fff_ffff
    (value % (10**DIGITS)).to_s.rjust(DIGITS, "0")
  end

  # Returns the time step the code matched, or nil. Pass the step returned by
  # the last successful verification as `after:` so a code can't be replayed.
  def verify(secret, code, after: nil, at: Time.now)
    code = code.to_s.gsub(/[\s-]/, "")
    return nil unless code.match?(/\A\d{#{DIGITS}}\z/)

    now = time_step(at)
    (now - DRIFT_STEPS..now + DRIFT_STEPS).find do |step|
      next false if after && step <= after

      OpenSSL.fixed_length_secure_compare(code_at(secret, step), code)
    end
  end

  # The otpauth:// URI that authenticator apps read from the QR code.
  def provisioning_uri(secret, account:, issuer:)
    label = uri_escape("#{issuer}:#{account}")
    "otpauth://totp/#{label}?secret=#{secret}&issuer=#{uri_escape(issuer)}" \
      "&algorithm=SHA1&digits=#{DIGITS}&period=#{PERIOD}"
  end

  # Groups the secret in fours for people typing it in by hand.
  def display_secret(secret)
    secret.scan(/.{1,4}/).join(" ")
  end

  def base32_encode(bytes)
    bytes.unpack1("B*").scan(/.{1,5}/).map { |chunk| BASE32_ALPHABET[chunk.ljust(5, "0").to_i(2)] }.join
  end

  def base32_decode(text)
    bits = text.to_s.upcase.delete("= ").each_char.map do |char|
      index = BASE32_ALPHABET.index(char) or raise ArgumentError, "invalid base32 character"
      index.to_s(2).rjust(5, "0")
    end.join
    [bits[0, bits.length / 8 * 8]].pack("B*")
  end

  def uri_escape(text)
    text.to_s.b.gsub(/[^A-Za-z0-9_.~-]/) { |char| format("%%%02X", char.ord) }
  end
end
