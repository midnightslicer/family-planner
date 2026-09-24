require "json"
require "openssl"
require "securerandom"

module WebAuthn
  # Builds ceremony options and verifies the browser's responses for one
  # relying party (this site). `id` is the RP ID (the bare host) and `origin`
  # the exact scheme://host[:port] the page is served from.
  #
  # Options are shaped like the WebAuthn JSON types
  # (PublicKeyCredentialCreationOptionsJSON / RequestOptionsJSON), with binary
  # fields as base64url, so the browser side can hand them straight over.
  class RelyingParty
    Registration = Struct.new(:credential_id, :public_key, :algorithm, :sign_count, :transports, :backed_up, keyword_init: true)

    FLAG_USER_PRESENT = 0x01
    FLAG_USER_VERIFIED = 0x04
    FLAG_BACKED_UP = 0x10
    FLAG_ATTESTED_DATA = 0x40
    TIMEOUT_MS = 300_000
    TRANSPORTS = %w[ble hybrid internal nfc smart-card usb].freeze

    attr_reader :id, :origin, :name

    def initialize(id:, origin:, name:)
      @id = id
      @origin = origin
      @name = name
    end

    def self.challenge
      Base64Url.encode(SecureRandom.random_bytes(32))
    end

    # user_handle: opaque random bytes (never an email or database id).
    def registration_options(challenge:, user_handle:, user_name:, display_name:, exclude: [])
      {
        challenge: challenge,
        rp: { id: id, name: name },
        user: { id: Base64Url.encode(user_handle), name: user_name, displayName: display_name },
        pubKeyCredParams: CoseKey::SUPPORTED_ALGORITHMS.map { |alg| { type: "public-key", alg: alg } },
        timeout: TIMEOUT_MS,
        attestation: "none",
        authenticatorSelection: { residentKey: "required", requireResidentKey: true, userVerification: "required" },
        excludeCredentials: exclude.map { |credential_id| { type: "public-key", id: credential_id } }
      }
    end

    # No allowCredentials: passkeys are discoverable, so the browser offers
    # whichever ones it holds for this site and the email field can stay empty.
    def authentication_options(challenge:)
      { challenge: challenge, rpId: id, timeout: TIMEOUT_MS, userVerification: "required", allowCredentials: [] }
    end

    def verify_registration(credential, challenge:)
      response = fetch(credential, "response")
      client_data_json = decode_field(response, "clientDataJSON")
      verify_client_data(client_data_json, "webauthn.create", challenge)

      attestation = Cbor.decode(decode_field(response, "attestationObject"))
      raise Error, "malformed attestation" unless attestation.is_a?(Hash) && attestation["authData"].is_a?(String)

      auth_data = attestation["authData"].b
      flags, sign_count = verify_authenticator_data(auth_data)
      raise Error, "no credential in response" unless flags & FLAG_ATTESTED_DATA != 0
      raise Error, "authenticator data too short" if auth_data.bytesize < 55

      id_length = auth_data.byteslice(53, 2).unpack1("n")
      credential_id = auth_data.byteslice(55, id_length)
      raise Error, "authenticator data too short" unless credential_id&.bytesize == id_length
      raise Error, "credential id mismatch" unless credential_id == decode_field(credential, "rawId")

      cose, = Cbor.decode_prefix(auth_data.byteslice(55 + id_length..))
      public_key, algorithm = CoseKey.to_der(cose)

      Registration.new(
        credential_id: Base64Url.encode(credential_id),
        public_key: public_key,
        algorithm: algorithm,
        sign_count: sign_count,
        transports: Array(response["transports"]).map(&:to_s) & TRANSPORTS,
        backed_up: flags & FLAG_BACKED_UP != 0
      )
    end

    # Checks an assertion against the stored key. Returns the new signature
    # counter, which the caller must save.
    def verify_authentication(credential, challenge:, public_key:, algorithm:, sign_count:)
      response = fetch(credential, "response")
      client_data_json = decode_field(response, "clientDataJSON")
      verify_client_data(client_data_json, "webauthn.get", challenge)

      auth_data = decode_field(response, "authenticatorData")
      _flags, new_count = verify_authenticator_data(auth_data)

      signed = auth_data + OpenSSL::Digest::SHA256.digest(client_data_json)
      unless CoseKey.verify_signature(public_key, algorithm, decode_field(response, "signature"), signed)
        raise Error, "signature did not verify"
      end

      # A counter that fails to advance suggests a cloned authenticator. Synced
      # passkeys always report 0, which is allowed.
      if (new_count.positive? || sign_count.positive?) && new_count <= sign_count
        raise Error, "signature counter went backwards"
      end

      new_count
    end

    private

    def fetch(hash, key)
      value = hash.is_a?(Hash) ? (hash[key] || hash[key.to_sym]) : nil
      raise Error, "missing #{key}" if value.nil?

      value
    end

    def decode_field(hash, key)
      value = fetch(hash, key)
      raise Error, "malformed #{key}" unless value.is_a?(String)

      Base64Url.decode(value)
    end

    def verify_client_data(json, type, challenge)
      data = JSON.parse(json)
      raise Error, "malformed client data" unless data.is_a?(Hash)
      raise Error, "wrong ceremony type" unless data["type"] == type
      raise Error, "challenge mismatch" unless challenge.is_a?(String) && data["challenge"].is_a?(String) &&
        OpenSSL.secure_compare(data["challenge"], challenge)
      raise Error, "origin mismatch" unless data["origin"] == origin
      raise Error, "cross-origin ceremony" if data["crossOrigin"] == true
    rescue JSON::ParserError
      raise Error, "malformed client data"
    end

    # Returns [flags, sign_count] after checking the RP ID hash and that the
    # user was present and verified (PIN, biometric or device passcode).
    def verify_authenticator_data(auth_data)
      raise Error, "authenticator data too short" if auth_data.bytesize < 37

      rp_id_hash = auth_data.byteslice(0, 32)
      unless OpenSSL.secure_compare(rp_id_hash, OpenSSL::Digest::SHA256.digest(id))
        raise Error, "credential belongs to another site"
      end

      flags = auth_data.getbyte(32)
      raise Error, "user presence required" if flags & FLAG_USER_PRESENT == 0
      raise Error, "user verification required" if flags & FLAG_USER_VERIFIED == 0

      [flags, auth_data.byteslice(33, 4).unpack1("N")]
    end
  end
end
