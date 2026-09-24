# Server side of WebAuthn passkeys, on the Ruby standard library only.
#
# Registration asks for "none" attestation, so what we verify is what matters
# for passkeys: the challenge, origin and RP ID bind each ceremony to this
# site and this session, the flags prove user presence and verification, and
# every sign-in checks the authenticator's signature against the public key
# stored at registration.
module WebAuthn
  class Error < StandardError; end

  module Base64Url
    module_function

    def encode(bytes)
      [bytes].pack("m0").tr("+/", "-_").delete("=")
    end

    def decode(text)
      text = text.to_s.tr("-_", "+/")
      text += "=" * ((4 - text.length % 4) % 4)
      text.unpack1("m0")
    rescue ArgumentError
      raise Error, "malformed base64url"
    end
  end
end
