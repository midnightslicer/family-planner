require "test_helper"

class WebAuthnTest < ActiveSupport::TestCase
  ORIGIN = "https://status.example.com".freeze

  setup do
    @rp = WebAuthn::RelyingParty.new(id: "status.example.com", origin: ORIGIN, name: "Family Status")
    @authenticator = FakeAuthenticator.new(rp_id: "status.example.com", origin: ORIGIN)
  end

  def register(authenticator = @authenticator)
    challenge = WebAuthn::RelyingParty.challenge
    @rp.verify_registration(authenticator.create(challenge: challenge), challenge: challenge)
  end

  test "registration options describe a discoverable, verified passkey" do
    options = @rp.registration_options(challenge: "abc", user_handle: "\x01\x02".b, user_name: "sam@example.com",
                                       display_name: "Sam", exclude: ["cred1"])
    assert_equal "status.example.com", options[:rp][:id]
    assert_equal "AQI", options[:user][:id]
    assert_equal "required", options[:authenticatorSelection][:residentKey]
    assert_equal "required", options[:authenticatorSelection][:userVerification]
    assert_equal [{ type: "public-key", id: "cred1" }], options[:excludeCredentials]
  end

  test "registration returns the credential and a loadable public key" do
    registration = register
    assert_equal @authenticator.encoded_id, registration.credential_id
    assert_equal WebAuthn::CoseKey::ES256, registration.algorithm
    assert_equal ["internal"], registration.transports
    assert_equal @authenticator.key.public_to_der, registration.public_key
  end

  test "registration rejects a replayed or foreign challenge" do
    response = @authenticator.create(challenge: "one")
    assert_raises(WebAuthn::Error) { @rp.verify_registration(response, challenge: "two") }
  end

  test "registration rejects the wrong origin, rp id, type or missing verification" do
    challenge = "c"
    [
      @authenticator.create(challenge: challenge, origin: "https://evil.example"),
      @authenticator.create(challenge: challenge, rp_id: "evil.example"),
      @authenticator.create(challenge: challenge, type: "webauthn.get"),
      @authenticator.create(challenge: challenge, flags: 0x41) # present but not verified
    ].each do |response|
      assert_raises(WebAuthn::Error) { @rp.verify_registration(response, challenge: challenge) }
    end
  end

  test "registration rejects garbage without raising anything else" do
    ["", nil, {}, { "response" => { "clientDataJSON" => "!!", "attestationObject" => "AA" } }].each do |junk|
      assert_raises(WebAuthn::Error) { @rp.verify_registration(junk, challenge: "c") }
    end
  end

  test "authentication verifies the signature" do
    registration = register
    challenge = WebAuthn::RelyingParty.challenge
    count = @rp.verify_authentication(@authenticator.get(challenge: challenge), challenge: challenge,
                                      public_key: registration.public_key, algorithm: registration.algorithm, sign_count: 0)
    assert_equal 0, count
  end

  test "authentication works with Ed25519 keys" do
    authenticator = FakeAuthenticator.new(rp_id: "status.example.com", origin: ORIGIN, algorithm: :ed25519)
    registration = register(authenticator)
    assert_equal WebAuthn::CoseKey::EDDSA, registration.algorithm

    challenge = WebAuthn::RelyingParty.challenge
    assert_equal 0, @rp.verify_authentication(authenticator.get(challenge: challenge), challenge: challenge,
                                              public_key: registration.public_key, algorithm: registration.algorithm, sign_count: 0)
  end

  test "authentication rejects a signature from a different key" do
    registration = register
    impostor = FakeAuthenticator.new(rp_id: "status.example.com", origin: ORIGIN)
    challenge = "c"
    assert_raises(WebAuthn::Error) do
      @rp.verify_authentication(impostor.get(challenge: challenge), challenge: challenge,
                                public_key: registration.public_key, algorithm: registration.algorithm, sign_count: 0)
    end
  end

  test "authentication rejects a tampered client data" do
    registration = register
    response = @authenticator.get(challenge: "c")
    data = JSON.parse(WebAuthn::Base64Url.decode(response["response"]["clientDataJSON"]))
    data["challenge"] = "d"
    response["response"]["clientDataJSON"] = WebAuthn::Base64Url.encode(JSON.generate(data))
    assert_raises(WebAuthn::Error) do
      @rp.verify_authentication(response, challenge: "d", public_key: registration.public_key,
                                algorithm: registration.algorithm, sign_count: 0)
    end
  end

  test "authentication rejects a counter that does not advance" do
    authenticator = FakeAuthenticator.new(rp_id: "status.example.com", origin: ORIGIN, sign_count: 5)
    registration = register(authenticator)
    challenge = "c"
    response = authenticator.get(challenge: challenge) # count 6
    assert_equal 6, @rp.verify_authentication(response, challenge: challenge, public_key: registration.public_key,
                                              algorithm: registration.algorithm, sign_count: 5)
    assert_raises(WebAuthn::Error) do
      @rp.verify_authentication(response, challenge: challenge, public_key: registration.public_key,
                                algorithm: registration.algorithm, sign_count: 6)
    end
  end

  test "cbor decoder handles the common types and refuses truncation" do
    assert_equal({ 1 => [-1, "a", "\x00".b], "k" => true },
                 WebAuthn::Cbor.decode("\xA2\x01\x83\x20\x61\x61\x41\x00\x61\x6B\xF5".b))
    assert_raises(WebAuthn::Error) { WebAuthn::Cbor.decode("\x5A\xFF\xFF\xFF\xFF".b) }
    assert_raises(WebAuthn::Error) { WebAuthn::Cbor.decode("\x9B\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF".b) }
    assert_raises(WebAuthn::Error) { WebAuthn::Cbor.decode("\x81".b * 40 + "\x00".b) }
  end
end
