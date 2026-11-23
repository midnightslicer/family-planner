require "openssl"

module WebPush
  # Message encryption for Web Push (RFC 8291), in the aes128gcm content
  # coding (RFC 8188): one record, so the whole payload must fit in it.
  #
  # The browser gave us its public key (p256dh) and an auth secret when it
  # subscribed. Each message uses a fresh ephemeral key pair and salt, so
  # the push service only ever sees ciphertext.
  module Encryption
    RECORD_SIZE = 4096
    TAG_LENGTH = 16
    KEY_LENGTH = 65 # uncompressed P-256 point
    HEADER_LENGTH = 16 + 4 + 1 + KEY_LENGTH
    # Push services accept 4096 bytes of body: header, one 0x02 delimiter
    # byte and the GCM tag leave this much for the message itself.
    MAX_PLAINTEXT = RECORD_SIZE - HEADER_LENGTH - 1 - TAG_LENGTH

    module_function

    # Returns the request body. `ephemeral_key` and `salt` are only passed
    # by tests (the RFC 8291 appendix vector); normally both are fresh.
    def encrypt(plaintext, p256dh:, auth:, ephemeral_key: nil, salt: nil)
      plaintext = plaintext.to_s.b
      raise Error, "push payload too large (#{plaintext.bytesize} bytes)" if plaintext.bytesize > MAX_PLAINTEXT
      raise Error, "invalid auth secret" unless auth.is_a?(String) && auth.bytesize == 16

      ua_public = p256dh.to_s.b
      ua_point = point(ua_public)
      as_key = ephemeral_key || OpenSSL::PKey::EC.generate("prime256v1")
      as_public = as_key.public_key.to_octet_string(:uncompressed)
      salt ||= SecureRandom.random_bytes(16)

      ecdh_secret = as_key.dh_compute_key(ua_point)
      ikm = hkdf(ecdh_secret, salt: auth, info: "WebPush: info\0".b + ua_public + as_public, length: 32)
      cek = hkdf(ikm, salt: salt, info: "Content-Encoding: aes128gcm\0".b, length: 16)
      nonce = hkdf(ikm, salt: salt, info: "Content-Encoding: nonce\0".b, length: 12)

      cipher = OpenSSL::Cipher.new("aes-128-gcm").encrypt
      cipher.key = cek
      cipher.iv = nonce
      # 0x02: this is the last (only) record; no further padding.
      ciphertext = cipher.update(plaintext + "\x02".b) + cipher.final + cipher.auth_tag(TAG_LENGTH)

      salt + [RECORD_SIZE].pack("N") + [as_public.bytesize].pack("C") + as_public + ciphertext
    end

    # The browser's public key as a point on P-256 (rejects anything else).
    def point(bytes)
      raise Error, "invalid p256dh key" unless bytes.bytesize == KEY_LENGTH && bytes.getbyte(0) == 4

      group = OpenSSL::PKey::EC::Group.new("prime256v1")
      OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new(bytes, 2))
    rescue OpenSSL::PKey::EC::Point::Error, OpenSSL::PKey::ECError
      raise Error, "invalid p256dh key"
    end

    def hkdf(ikm, salt:, info:, length:)
      OpenSSL::KDF.hkdf(ikm, salt: salt, info: info, length: length, hash: "SHA256")
    end
  end
end
