require "test_helper"

class PasskeyTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
  end

  test "a signed-in member adds a passkey and signs in with it later" do
    sign_in @member
    authenticator = register_passkey
    passkey = @member.passkeys.sole
    assert_equal authenticator.key.public_to_der, passkey.public_key
    assert @member.reload.webauthn_id.present?

    delete destroy_user_session_path
    sign_in_with_passkey(authenticator)
    assert_response :success
    assert_equal root_path, response.parsed_body["redirect"]

    get root_path
    assert_response :success
    assert passkey.reload.last_used_at
  end

  # Regression: Devise's remember-me cookie came from the password hash, so
  # an account with no password crashed (500) on passkey sign-in.
  test "an account with only a passkey signs in with it and stays signed in" do
    sign_in @member
    authenticator = register_passkey
    @member.update_column(:encrypted_password, "")
    assert_not @member.reload.password_set?

    delete destroy_user_session_path
    sign_in_with_passkey(authenticator)
    assert_response :success
    assert cookies["remember_user_token"].present?

    get root_path
    assert_response :success
  end

  test "an account with only a passkey can get back in by email and set a password" do
    @member.update_column(:encrypted_password, "")

    perform_enqueued_jobs do
      post user_password_path, params: { user: { email: @member.email } }
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [@member.email], mail.to
    token = mail.body.encoded[/reset_password_token=([^"&\s]+)/, 1]
    assert token

    get edit_user_password_path(reset_password_token: token)
    assert_response :success
    put user_password_path, params: { user: { reset_password_token: token, password: "a-new-long-password", password_confirmation: "a-new-long-password" } }
    assert @member.reload.password_set?
    assert @member.valid_password?("a-new-long-password")
    assert_redirected_to new_user_session_path # then signs in with it

    post user_session_path, params: { user: { email: @member.email, password: "a-new-long-password" } }
    get root_path
    assert_response :success
  end

  test "sign-in options reuse no challenge" do
    sign_in @member
    authenticator = register_passkey
    delete destroy_user_session_path

    post user_passkey_options_path, as: :json
    stale = authenticator.get(challenge: response.parsed_body["challenge"])
    authenticator.user_handle = WebAuthn::Base64Url.decode(@member.reload.webauthn_id)
    post user_passkey_session_path, params: { credential: stale }, as: :json
    assert_response :success

    delete destroy_user_session_path
    post user_passkey_session_path, params: { credential: stale }, as: :json
    assert_response :unprocessable_content
  end

  test "a passkey from another key pair is refused" do
    sign_in @member
    authenticator = register_passkey
    delete destroy_user_session_path

    impostor = new_authenticator
    impostor.instance_variable_set(:@credential_id, authenticator.credential_id)
    impostor.user_handle = WebAuthn::Base64Url.decode(@member.reload.webauthn_id)
    post user_passkey_options_path, as: :json
    post user_passkey_session_path, params: { credential: impostor.get(challenge: response.parsed_body["challenge"]) }, as: :json
    assert_response :unprocessable_content

    get root_path
    assert_redirected_to new_user_session_path
  end

  test "a passkey made for another site is refused" do
    sign_in @member
    post options_account_passkeys_path, as: :json
    credential = new_authenticator.create(challenge: response.parsed_body["challenge"], rp_id: "evil.example")
    post account_passkeys_path, params: { credential: credential }, as: :json
    assert_response :unprocessable_content
    assert_empty @member.passkeys
  end

  test "the last way to sign in can't be removed" do
    @member.update_column(:encrypted_password, "")
    sign_in @member
    register_passkey
    passkey = @member.passkeys.sole

    delete account_passkey_path(passkey)
    assert passkey.reload.persisted?

    register_passkey
    delete account_passkey_path(passkey)
    assert_not Passkey.exists?(passkey.id)
  end

  test "someone else's passkey can't be removed or renamed" do
    sign_in @member
    register_passkey
    passkey = @member.passkeys.sole

    sign_out @member
    sign_in users(:admin)
    delete account_passkey_path(passkey)
    assert_response :not_found
    sign_in users(:admin) # a 404 doesn't save the session, and sign_in only applies to the next request
    patch account_passkey_path(passkey), params: { passkey: { name: "mine now" } }
    assert_response :not_found
  end
end
