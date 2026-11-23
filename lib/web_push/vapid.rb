require "openssl"
require "json"

module WebPush
  # Voluntary Application Server Identification (RFC 8292): every push is
  # sent with a short-lived JWT signed by our P-256 key, and the public half
  # is what browsers subscribe against (applicationServerKey). A push
  # service refuses pushes signed by any other key.
  class Vapid
    EXPIRY = 12 * 60 * 60 # seconds; RFC 8292 allows at most 24 hours

    attr_reader :key, :subject

    # `key`: an OpenSSL::PKey::EC private key on P-256. `subject`: a
    # mailto: or https: URL push services can use to reach whoever runs it.
    def initialize(key:, subject:)
      raise Error, "VAPID key must be a P-256 private key" unless key.is_a?(OpenSSL::PKey::EC) && key.private? &&
        key.group.curve_name == "prime256v1"

      @key = key
      @subject = subject
    end

    def self.generate_key
      OpenSSL::PKey::EC.generate("prime256v1")
    end

    # A private key from its raw 32-byte scalar (the form the web-push
    # libraries print as VAPID_PRIVATE_KEY, base64url-encoded).
    def self.key_from_private_bytes(bytes)
      raise Error, "VAPID private key must be 32 bytes" unless bytes.bytesize == 32

      group = OpenSSL::PKey::EC::Group.new("prime256v1")
      public_point = group.generator.mul(OpenSSL::BN.new(bytes, 2))
      der = OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::Integer(1),
        OpenSSL::ASN1::OctetString(bytes),
        OpenSSL::ASN1::ObjectId("prime256v1", 0, :EXPLICIT),
        OpenSSL::ASN1::BitString(public_point.to_octet_string(:uncompressed), 1, :EXPLICIT)
      ]).to_der
      OpenSSL::PKey::EC.new(der)
    rescue OpenSSL::PKey::PKeyError, OpenSSL::PKey::EC::Point::Error
      raise Error, "invalid VAPID private key"
    end

    # The raw uncompressed public point (65 bytes), base64url: what the
    # browser needs as applicationServerKey, and the `k` in every request.
    def public_key
      Base64Url.encode(key.public_key.to_octet_string(:uncompressed))
    end

    def private_key_bytes
      key.private_key.to_s(2).rjust(32, "\0".b)
    end

    # The Authorization header for a request to `endpoint`.
    def authorization(endpoint, now: Time.now)
      "vapid t=#{token(audience(endpoint), expires_at: now.to_i + EXPIRY)}, k=#{public_key}"
    end

    def token(audience, expires_at:)
      header = Base64Url.encode(JSON.generate(typ: "JWT", alg: "ES256"))
      claims = Base64Url.encode(JSON.generate(aud: audience, exp: expires_at, sub: subject))
      signing_input = "#{header}.#{claims}"
      "#{signing_input}.#{Base64Url.encode(raw_signature(signing_input))}"
    end

    # The push service's origin: scheme, host and any non-default port.
    def audience(endpoint)
      uri = URI.parse(endpoint)
      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "#{uri.scheme}://#{uri.host}#{port}"
    end

    private

    # JWS ES256 wants r || s, 32 bytes each, not OpenSSL's DER sequence.
    def raw_signature(data)
      der = key.sign("SHA256", data)
      OpenSSL::ASN1.decode(der).value.map { |integer| integer.value.to_s(2).rjust(32, "\0".b) }.join
    end
  end
end
