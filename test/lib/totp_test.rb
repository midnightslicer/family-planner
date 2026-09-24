require "test_helper"

class TotpTest < ActiveSupport::TestCase
  # RFC 6238 appendix B uses the ASCII secret "12345678901234567890" (SHA-1);
  # the six-digit codes are the last six digits of the published 8-digit ones.
  RFC_SECRET = Totp.base32_encode("12345678901234567890")

  test "matches the RFC 6238 test vectors" do
    {
      59 => "287082",
      1_111_111_109 => "081804",
      1_111_111_111 => "050471",
      1_234_567_890 => "005924",
      2_000_000_000 => "279037",
      20_000_000_000 => "353130"
    }.each do |time, expected|
      assert_equal expected, Totp.code_at(RFC_SECRET, time / Totp::PERIOD), "at #{time}"
    end
  end

  test "base32 round-trips arbitrary bytes" do
    20.times do
      bytes = SecureRandom.random_bytes(rand(1..40))
      assert_equal bytes, Totp.base32_decode(Totp.base32_encode(bytes))
    end
    assert_equal "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", RFC_SECRET
  end

  test "verify accepts the current and adjacent steps, returning the step" do
    secret = Totp.random_secret
    now = Time.at(1_700_000_000)
    step = Totp.time_step(now)

    assert_equal step, Totp.verify(secret, Totp.code_at(secret, step), at: now)
    assert_equal step - 1, Totp.verify(secret, Totp.code_at(secret, step - 1), at: now)
    assert_equal step + 1, Totp.verify(secret, Totp.code_at(secret, step + 1), at: now)
    assert_nil Totp.verify(secret, Totp.code_at(secret, step - 3), at: now)
  end

  test "verify tolerates spaces but rejects junk" do
    secret = Totp.random_secret
    now = Time.at(1_700_000_000)
    code = Totp.code_at(secret, Totp.time_step(now))

    assert Totp.verify(secret, "#{code[0, 3]} #{code[3, 3]}", at: now)
    assert_nil Totp.verify(secret, "", at: now)
    assert_nil Totp.verify(secret, "12345", at: now)
    assert_nil Totp.verify(secret, "abcdef", at: now)
  end

  test "verify refuses a step at or before the last one used" do
    secret = Totp.random_secret
    now = Time.at(1_700_000_000)
    step = Totp.time_step(now)
    code = Totp.code_at(secret, step)

    assert_nil Totp.verify(secret, code, after: step, at: now)
    assert_equal step, Totp.verify(secret, code, after: step - 1, at: now)
  end

  test "provisioning uri escapes the label" do
    uri = Totp.provisioning_uri("ABCD", account: "sam@example.com", issuer: "The Smiths")
    assert_equal "otpauth://totp/The%20Smiths%3Asam%40example.com?secret=ABCD&issuer=The%20Smiths&algorithm=SHA1&digits=6&period=30", uri
  end
end
