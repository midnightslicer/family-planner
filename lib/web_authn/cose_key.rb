require "openssl"

module WebAuthn
  # Converts a COSE_Key (RFC 9053) from an authenticator into a DER-encoded
  # SubjectPublicKeyInfo that OpenSSL can load. Covers the three algorithms
  # passkey providers use in practice: ES256, EdDSA (Ed25519) and RS256.
  module CoseKey
    ES256 = -7
    EDDSA = -8
    RS256 = -257
    SUPPORTED_ALGORITHMS = [ES256, EDDSA, RS256].freeze

    KTY = 1
    ALG = 3
    KTY_OKP = 1
    KTY_EC2 = 2
    KTY_RSA = 3

    module_function

    # Returns [spki_der, algorithm].
    def to_der(cose)
      raise Error, "public key is not a COSE map" unless cose.is_a?(Hash)

      algorithm = cose[ALG]
      raise Error, "unsupported public key algorithm" unless SUPPORTED_ALGORITHMS.include?(algorithm)

      der =
        case [cose[KTY], algorithm]
        when [KTY_EC2, ES256] then ec2_der(cose)
        when [KTY_OKP, EDDSA] then okp_der(cose)
        when [KTY_RSA, RS256] then rsa_der(cose)
        else raise Error, "public key type does not match its algorithm"
        end

      OpenSSL::PKey.read(der) # rejects points off the curve and similar junk
      [der, algorithm]
    rescue OpenSSL::PKey::PKeyError, OpenSSL::ASN1::ASN1Error
      raise Error, "invalid public key"
    end

    def ec2_der(cose)
      x = cose[-2]
      y = cose[-3]
      raise Error, "unsupported curve" unless cose[-1] == 1 # P-256
      raise Error, "invalid EC coordinates" unless [x, y].all? { |c| c.is_a?(String) && c.bytesize == 32 }

      spki(
        [OpenSSL::ASN1::ObjectId.new("id-ecPublicKey"), OpenSSL::ASN1::ObjectId.new("prime256v1")],
        "\x04".b + x + y
      )
    end

    def okp_der(cose)
      x = cose[-2]
      raise Error, "unsupported curve" unless cose[-1] == 6 # Ed25519
      raise Error, "invalid Ed25519 key" unless x.is_a?(String) && x.bytesize == 32

      spki([OpenSSL::ASN1::ObjectId.new("ED25519")], x)
    end

    def rsa_der(cose)
      n = cose[-1]
      e = cose[-2]
      raise Error, "invalid RSA key" unless n.is_a?(String) && e.is_a?(String) && n.bytesize >= 256

      key = OpenSSL::ASN1::Sequence.new([
        OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(n, 2)),
        OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(e, 2))
      ])
      spki([OpenSSL::ASN1::ObjectId.new("rsaEncryption"), OpenSSL::ASN1::Null.new(nil)], key.to_der)
    end

    def spki(algorithm_identifier, key_bits)
      OpenSSL::ASN1::Sequence.new([
        OpenSSL::ASN1::Sequence.new(algorithm_identifier),
        OpenSSL::ASN1::BitString.new(key_bits)
      ]).to_der
    end

    def verify_signature(der, algorithm, signature, data)
      key = OpenSSL::PKey.read(der)
      digest = algorithm == EDDSA ? nil : "SHA256"
      key.verify(digest, signature, data)
    rescue OpenSSL::PKey::PKeyError
      false
    end
  end
end
