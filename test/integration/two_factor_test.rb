require "test_helper"

class TwoFactorTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
  end

  def enable_two_factor
    sign_in @member
    get new_account_two_factor_path
    assert_response :success
    assert_select ".qr-code"
    secret = css_select(".secret-key").first.text.delete(" ")
    post account_two_factor_path, params: { code: Totp.code_at(secret, Totp.time_step) }
    assert_response :success
    codes = css_select(".recovery-codes code").map(&:text)
    assert_equal User::RECOVERY_CODE_COUNT, codes.size
    delete destroy_user_session_path
    [secret, codes]
  end

  def password_step
    post user_session_path, params: { user: { email: @member.email, password: "password" } }
    assert_redirected_to user_two_factor_path
  end

  test "a wrong setup code leaves two-step verification off" do
    sign_in @member
    get new_account_two_factor_path
    post account_two_factor_path, params: { code: "000000" }
    assert_response :unprocessable_content
    assert_not @member.reload.two_factor_enabled?
  end

  test "password sign-in then needs the current code" do
    secret, = enable_two_factor
    password_step

    get dashboard_path
    assert_redirected_to new_user_session_path, "not signed in after the password alone"

    post user_two_factor_path, params: { code: "000000" }
    assert_response :unprocessable_content

    post user_two_factor_path, params: { code: Totp.code_at(secret, Totp.time_step + 1) }
    assert_redirected_to dashboard_root_path
    get dashboard_path
    assert_response :success
  end

  test "a code can't be used twice" do
    secret, = enable_two_factor
    code = Totp.code_at(secret, Totp.time_step + 1)
    password_step
    post user_two_factor_path, params: { code: code }
    delete destroy_user_session_path

    password_step
    post user_two_factor_path, params: { code: code }
    assert_response :unprocessable_content
  end

  test "recovery codes work once each" do
    _, codes = enable_two_factor
    password_step
    post user_two_factor_path, params: { code: codes.first.upcase }
    assert_redirected_to dashboard_root_path
    assert_equal User::RECOVERY_CODE_COUNT - 1, @member.reload.recovery_codes_remaining
    delete destroy_user_session_path

    password_step
    post user_two_factor_path, params: { code: codes.first }
    assert_response :unprocessable_content
  end

  test "the code step can't be reached without the password" do
    enable_two_factor
    get user_two_factor_path
    assert_redirected_to new_user_session_path
    post user_two_factor_path, params: { code: "123456" }
    assert_redirected_to new_user_session_path
  end

  test "a wrong password never reaches the code step" do
    enable_two_factor
    post user_session_path, params: { user: { email: @member.email, password: "wrong" } }
    assert_response :unprocessable_content
  end

  test "turning it off needs a valid code" do
    secret, = enable_two_factor
    sign_in @member
    delete account_two_factor_path, params: { code: "000000" }
    assert @member.reload.two_factor_enabled?
    delete account_two_factor_path, params: { code: Totp.code_at(secret, Totp.time_step + 1) }
    assert_not @member.reload.two_factor_enabled?
  end

  test "an admin can reset someone's two-step verification" do
    enable_two_factor
    sign_in users(:admin)
    post reset_security_admin_user_path(@member)
    assert_not @member.reload.two_factor_enabled?
  end
end
