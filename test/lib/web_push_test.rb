require "test_helper"

class WebPushTest < ActiveSupport::TestCase
  B64 = WebPush::Base64Url

  # RFC 8291, Appendix A.
  RFC = {
    plaintext: "When I grow up, I want to be a watermelon",
    as_private: "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw",
    as_public: "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8",
    ua_private: "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94",
    ua_public: "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4",
    salt: "DGv6ra1nlYgDCS1FRnbzlw",
    auth: "BTBZMqHH6r4Tts7J_aSIgg",
    body: "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_" \
          "yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"
  }.freeze

  def rfc_key(name) = WebPush::Vapid.key_from_private_bytes(B64.decode(RFC[name]))

  # The browser's side of RFC 8291, so round trips check what a browser would see.
  def decrypt(body, ua_key:, auth:)
    salt = body[0, 16]
    record_size = body[16, 4].unpack1("N")
    key_length = body.getbyte(20)
    as_public = body[21, key_length]
    ciphertext = body[(21 + key_length)..]
    assert_equal 4096, record_size

    ua_public = ua_key.public_key.to_octet_string(:uncompressed)
    secret = ua_key.dh_compute_key(WebPush::Encryption.point(as_public))
    ikm = OpenSSL::KDF.hkdf(secret, salt: auth, info: "WebPush: info\0".b + ua_public + as_public, length: 32, hash: "SHA256")
    cek = OpenSSL::KDF.hkdf(ikm, salt: salt, info: "Content-Encoding: aes128gcm\0".b, length: 16, hash: "SHA256")
    nonce = OpenSSL::KDF.hkdf(ikm, salt: salt, info: "Content-Encoding: nonce\0".b, length: 12, hash: "SHA256")
    cipher = OpenSSL::Cipher.new("aes-128-gcm").decrypt
    cipher.key = cek
    cipher.iv = nonce
    cipher.auth_tag = ciphertext[-16..]
    record = cipher.update(ciphertext[0...-16]) + cipher.final
    record.delete_suffix("\x02".b)
  end

  test "encryption matches the RFC 8291 appendix vector" do
    as_key = rfc_key(:as_private)
    assert_equal RFC[:as_public], B64.encode(as_key.public_key.to_octet_string(:uncompressed))

    body = WebPush::Encryption.encrypt(RFC[:plaintext], p256dh: B64.decode(RFC[:ua_public]), auth: B64.decode(RFC[:auth]),
                                                        ephemeral_key: as_key, salt: B64.decode(RFC[:salt]))
    assert_equal RFC[:body], B64.encode(body)
    assert_equal RFC[:plaintext], decrypt(body, ua_key: rfc_key(:ua_private), auth: B64.decode(RFC[:auth]))
  end

  test "each message uses a fresh key and salt and still decrypts" do
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    auth = SecureRandom.random_bytes(16)
    p256dh = browser.public_key.to_octet_string(:uncompressed)
    one = WebPush::Encryption.encrypt("hello", p256dh: p256dh, auth: auth)
    two = WebPush::Encryption.encrypt("hello", p256dh: p256dh, auth: auth)
    assert_not_equal one, two
    assert_equal "hello", decrypt(one, ua_key: browser, auth: auth)
    assert_equal "hello", decrypt(two, ua_key: browser, auth: auth)
  end

  test "encryption rejects bad keys, bad secrets and oversized payloads" do
    p256dh = OpenSSL::PKey::EC.generate("prime256v1").public_key.to_octet_string(:uncompressed)
    auth = SecureRandom.random_bytes(16)
    assert_raises(WebPush::Error) { WebPush::Encryption.encrypt("x", p256dh: "\x04".b + "\x01".b * 64, auth: auth) }
    assert_raises(WebPush::Error) { WebPush::Encryption.encrypt("x", p256dh: p256dh[1..], auth: auth) }
    assert_raises(WebPush::Error) { WebPush::Encryption.encrypt("x", p256dh: p256dh, auth: "short") }
    assert_raises(WebPush::Error) { WebPush::Encryption.encrypt("x" * (WebPush::Encryption::MAX_PLAINTEXT + 1), p256dh: p256dh, auth: auth) }
    body = WebPush::Encryption.encrypt("x" * WebPush::Encryption::MAX_PLAINTEXT, p256dh: p256dh, auth: auth)
    assert_equal 4096, body.bytesize
  end

  test "the VAPID token is an ES256 JWT that verifies against the public key" do
    vapid = WebPush::Vapid.new(key: WebPush::Vapid.generate_key, subject: "mailto:board@example.com")
    now = Time.at(1_800_000_000)
    header = vapid.authorization("https://fcm.googleapis.com/fcm/send/abc", now: now)
    match = header.match(/\Avapid t=([^,]+), k=(\S+)\z/)
    assert match, header
    token, public_key = match.captures
    assert_equal vapid.public_key, public_key
    assert_equal 65, B64.decode(public_key).bytesize

    head, claims, signature = token.split(".")
    assert_equal({ "typ" => "JWT", "alg" => "ES256" }, JSON.parse(B64.decode(head)))
    assert_equal({ "aud" => "https://fcm.googleapis.com", "exp" => 1_800_000_000 + 12 * 3600, "sub" => "mailto:board@example.com" },
                 JSON.parse(B64.decode(claims)))

    raw = B64.decode(signature)
    assert_equal 64, raw.bytesize
    der = OpenSSL::ASN1::Sequence([ raw[0, 32], raw[32, 32] ].map { |half| OpenSSL::ASN1::Integer(OpenSSL::BN.new(half, 2)) }).to_der
    verifier = OpenSSL::PKey::EC.new(OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Sequence([ OpenSSL::ASN1::ObjectId("id-ecPublicKey"), OpenSSL::ASN1::ObjectId("prime256v1") ]),
      OpenSSL::ASN1::BitString(B64.decode(public_key))
    ]).to_der)
    assert verifier.verify("SHA256", der, "#{head}.#{claims}")
    assert_not verifier.verify("SHA256", der, "#{head}.#{claims}x")
  end

  test "the audience keeps a non-default port" do
    vapid = WebPush::Vapid.new(key: WebPush::Vapid.generate_key, subject: "https://status.example.com")
    assert_equal "https://web.push.apple.com", vapid.audience("https://web.push.apple.com/QGuQ")
    assert_equal "https://push.example:8443", vapid.audience("https://push.example:8443/x")
  end

  test "a key round-trips through its raw private bytes" do
    key = WebPush::Vapid.generate_key
    vapid = WebPush::Vapid.new(key: key, subject: "mailto:a@example.com")
    again = WebPush::Vapid.new(key: WebPush::Vapid.key_from_private_bytes(vapid.private_key_bytes), subject: "mailto:a@example.com")
    assert_equal vapid.public_key, again.public_key
    assert_raises(WebPush::Error) { WebPush::Vapid.key_from_private_bytes("short") }
    assert_raises(WebPush::Error) { WebPush::Vapid.new(key: OpenSSL::PKey::EC.generate("secp384r1"), subject: "x") }
  end

  test "only https endpoints on known push services are allowed" do
    %w[
      https://fcm.googleapis.com/fcm/send/abc:def
      https://web.push.apple.com/QGuQyavXutnMHk
      https://wns2-bl2p.notify.windows.com/w/?token=abc
      https://updates.push.services.mozilla.com/wpush/v2/gAAAA
      https://push.services.mozilla.com/wpush/v2/x
      HTTPS://FCM.GOOGLEAPIS.COM/fcm/send/abc
      https://jmt17.google.com/fcm/send/abc:def
    ].each { |url| assert WebPush.allowed_endpoint?(url), url }

    [
      "http://fcm.googleapis.com/fcm/send/abc",
      "https://fcm.googleapis.com:8443/fcm/send/abc",
      "https://user@fcm.googleapis.com/fcm/send/abc",
      "https://fcm.googleapis.com.evil.example/x",
      "https://evilfcm.googleapis.com/x",
      "https://push.apple.com/x",
      "https://evilpush.apple.com/x",
      "https://google.com/x",
      "https://evilgoogle.com/x",
      "https://jmt17.google.com.evil.example/x",
      "https://127.0.0.1/x",
      "https://localhost/x",
      "https://169.254.169.254/latest/meta-data",
      "ftp://fcm.googleapis.com/x",
      "javascript:alert(1)",
      "not a url",
      "",
      nil
    ].each { |url| assert_not WebPush.allowed_endpoint?(url), url.inspect }
  end

  test "the client refuses endpoints off the allowlist without connecting" do
    vapid = WebPush::Vapid.new(key: WebPush::Vapid.generate_key, subject: "mailto:a@example.com")
    result = WebPush::Client.new(vapid).deliver(endpoint: "https://127.0.0.1/x", p256dh: "", auth: "", payload: "{}")
    assert_equal :failed, result.status
  end

  def fake_response(code, body = "")
    Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new("1.1", code, "x").tap do |response|
      response.instance_variable_set(:@body, body)
      response.instance_variable_set(:@read, true)
    end
  end

  test "the client posts an encrypted, signed message and maps the answer to what to do next" do
    vapid = WebPush::Vapid.new(key: WebPush::Vapid.generate_key, subject: "mailto:a@example.com")
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    auth = SecureRandom.random_bytes(16)
    p256dh = browser.public_key.to_octet_string(:uncompressed)

    { "201" => :ok, "404" => :gone, "410" => :gone, "429" => :retry, "503" => :retry, "400" => :failed, "403" => :failed }.each do |code, status|
      sent = nil
      transport = ->(uri, request) { sent = [ uri, request ]; fake_response(code, "nope") }
      result = WebPush::Client.new(vapid, transport: transport)
                              .deliver(endpoint: "https://fcm.googleapis.com/fcm/send/abc", p256dh: p256dh, auth: auth,
                                       payload: '{"title":"hi"}', ttl: 60, urgency: "high", topic: "task-1")
      assert_equal status, result.status, code
      assert_equal code.to_i, result.code

      uri, request = sent
      assert_equal "https://fcm.googleapis.com/fcm/send/abc", uri.to_s
      assert_equal "POST", request.method
      assert_equal "aes128gcm", request["Content-Encoding"]
      assert_equal "60", request["TTL"]
      assert_equal "high", request["Urgency"]
      assert_equal "task-1", request["Topic"]
      assert_match(/\Avapid t=.+, k=#{vapid.public_key}\z/, request["Authorization"])
      assert_equal '{"title":"hi"}', decrypt(request.body, ua_key: browser, auth: auth)
    end
  end

  test "unusable topics and urgencies are dropped or defaulted" do
    vapid = WebPush::Vapid.new(key: WebPush::Vapid.generate_key, subject: "mailto:a@example.com")
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    sent = nil
    WebPush::Client.new(vapid, transport: ->(_uri, request) { sent = request; fake_response("201") })
                   .deliver(endpoint: "https://fcm.googleapis.com/fcm/send/abc", p256dh: browser.public_key.to_octet_string(:uncompressed),
                            auth: SecureRandom.random_bytes(16), payload: "{}", urgency: "panic", topic: "has spaces")
    assert_equal "normal", sent["Urgency"]
    assert_nil sent["Topic"]
  end

  test "network trouble means try again later" do
    vapid = WebPush::Vapid.new(key: WebPush::Vapid.generate_key, subject: "mailto:a@example.com")
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    result = WebPush::Client.new(vapid, transport: ->(*) { raise Net::OpenTimeout })
                            .deliver(endpoint: "https://fcm.googleapis.com/fcm/send/abc", p256dh: browser.public_key.to_octet_string(:uncompressed),
                                     auth: SecureRandom.random_bytes(16), payload: "{}")
    assert_equal :retry, result.status
  end

  test "a subscription with broken keys fails instead of raising" do
    vapid = WebPush::Vapid.new(key: WebPush::Vapid.generate_key, subject: "mailto:a@example.com")
    result = WebPush::Client.new(vapid, transport: ->(*) { flunk "should not send" })
                            .deliver(endpoint: "https://fcm.googleapis.com/fcm/send/abc", p256dh: "junk", auth: "junk", payload: "{}")
    assert_equal :failed, result.status
  end
end
