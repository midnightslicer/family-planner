require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "handles are derived from the display name and kept unique" do
    first = User.create!(display_name: "Sam Smith", email: "sam1@example.com", password: "long enough pw")
    second = User.create!(display_name: "Sam Smith", email: "sam2@example.com", password: "long enough pw")
    assert_equal "sam_smith", first.handle
    assert_equal "sam_smith_2", second.handle
  end

  test "a password is required unless signing up with a passkey" do
    user = User.new(display_name: "Kid", email: "kid@example.com")
    assert_not user.valid?
    assert user.errors.include?(:password)

    user.signing_up_with_passkey = true
    assert user.valid?
  end

  test "two-factor setup needs a correct code and returns recovery codes" do
    user = users(:member)
    secret = Totp.random_secret
    assert_nil user.enable_two_factor!(secret, "000000") unless Totp.code_at(secret, Totp.time_step) == "000000"

    codes = user.enable_two_factor!(secret, Totp.code_at(secret, Totp.time_step))
    assert_equal User::RECOVERY_CODE_COUNT, codes.size
    assert user.two_factor_enabled?
    assert_not_includes user.reload.otp_recovery_codes, codes.first, "only digests are stored"
    assert_not_equal secret, user.read_attribute_before_type_cast(:otp_secret), "the secret is encrypted at rest"
  end

  test "suggested colors avoid ones already used in the household" do
    household = households(:smiths)
    taken = household.users.pluck(:color)
    20.times { assert_not_includes taken, User.suggested_color(household) }
  end

  test "resetting sign-in security clears passkeys and 2FA" do
    user = users(:member)
    secret = Totp.random_secret
    user.enable_two_factor!(secret, Totp.code_at(secret, Totp.time_step))
    user.passkeys.create!(external_id: "abc", public_key: "x", algorithm: -7, name: "Phone")

    user.reset_sign_in_security!
    assert_not user.reload.two_factor_enabled?
    assert_empty user.passkeys
  end
end
