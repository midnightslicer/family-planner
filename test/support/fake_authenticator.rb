require "json"
require "openssl"
require "securerandom"

# A software passkey for tests: produces the same JSON a browser sends from
# navigator.credentials.create()/get(), signed with a real key pair, so the
# server-side verification runs end to end.
class FakeAuthenticator
  attr_reader :credential_id, :key, :sign_count
  attr_accessor :user_handle

  def initialize(rp_id:, origin:, algorithm: :es256, sign_count: 0)
    @rp_id = rp_id
    @origin = origin
    @algorithm = algorithm
    @sign_count = sign_count
    @credential_id = SecureRandom.random_bytes(16)
    @key = algorithm == :ed25519 ? OpenSSL::PKey.generate_key("ED25519") : OpenSSL::PKey::EC.generate("prime256v1")
  end

  def encoded_id
    WebAuthn::Base64Url.encode(credential_id)
  end

  def create(challenge:, origin: @origin, rp_id: @rp_id, flags: 0x45, type: "webauthn.create")
    client_data = client_data_json(type, challenge, origin)
    attested = [0].pack("C") * 16 + [credential_id.bytesize].pack("n") + credential_id + cbor(cose_key)
    auth_data = authenticator_data(rp_id, flags) + attested
    attestation = cbor({ "fmt" => "none", "attStmt" => {}, "authData" => auth_data })
    {
      "id" => encoded_id,
      "rawId" => encoded_id,
      "type" => "public-key",
      "response" => {
        "clientDataJSON" => b64(client_data),
        "attestationObject" => b64(attestation),
        "transports" => ["internal", "bogus"]
      }
    }
  end

  def get(challenge:, origin: @origin, rp_id: @rp_id, flags: 0x05, type: "webauthn.get")
    @sign_count += 1 if @sign_count.positive?
    client_data = client_data_json(type, challenge, origin)
    auth_data = authenticator_data(rp_id, flags)
    signed = auth_data + OpenSSL::Digest::SHA256.digest(client_data)
    signature = @algorithm == :ed25519 ? key.sign(nil, signed) : key.sign("SHA256", signed)
    {
      "id" => encoded_id,
      "rawId" => encoded_id,
      "type" => "public-key",
      "response" => {
        "clientDataJSON" => b64(client_data),
        "authenticatorData" => b64(auth_data),
        "signature" => b64(signature),
        "userHandle" => user_handle && b64(user_handle)
      }
    }
  end

  private

  def b64(bytes)
    WebAuthn::Base64Url.encode(bytes)
  end

  def client_data_json(type, challenge, origin)
    JSON.generate({ type: type, challenge: challenge, origin: origin, crossOrigin: false })
  end

  def authenticator_data(rp_id, flags)
    OpenSSL::Digest::SHA256.digest(rp_id) + [flags].pack("C") + [@sign_count].pack("N")
  end

  def cose_key
    if @algorithm == :ed25519
      raw = key.raw_public_key
      { 1 => 1, 3 => -8, -1 => 6, -2 => raw }
    else
      point = key.public_key.to_octet_string(:uncompressed)
      { 1 => 2, 3 => -7, -1 => 1, -2 => point.byteslice(1, 32), -3 => point.byteslice(33, 32) }
    end
  end

  # Just enough CBOR encoding for the structures above.
  def cbor(value)
    case value
    when Integer
      value.negative? ? cbor_head(1, -1 - value) : cbor_head(0, value)
    when String
      value.encoding == Encoding::BINARY ? cbor_head(2, value.bytesize) + value : cbor_head(3, value.bytesize) + value.b
    when Hash
      value.inject(cbor_head(5, value.size)) { |out, (k, v)| out + cbor(k) + cbor(v) }
    when Array
      value.inject(cbor_head(4, value.size)) { |out, v| out + cbor(v) }
    end
  end

  def cbor_head(major, argument)
    type = major << 5
    if argument < 24 then [type | argument].pack("C")
    elsif argument < 256 then [type | 24, argument].pack("CC")
    elsif argument < 65_536 then [type | 25, argument].pack("Cn")
    else [type | 26, argument].pack("CN")
    end
  end
end
