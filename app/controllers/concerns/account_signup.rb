# Account creation for the setup wizard and invitation links. People can
# sign up with a passkey (no password at all) or a password.
#
# The passkey path is two requests: #passkey_options validates the profile
# fields first (so a typo doesn't leave an orphaned passkey on the device)
# and returns registration options; the browser creates the passkey and the
# form is submitted with the credential in `passkey_credential`, which
# #attach_signup_passkey verifies before the account is saved.
module AccountSignup
  extend ActiveSupport::Concern

  private

  def render_signup_passkey_options(user)
    user.signing_up_with_passkey = true
    return render_json_error(user.errors.full_messages.to_sentence) unless user.valid?

    handle = SecureRandom.random_bytes(32)
    challenge = start_ceremony(:passkey_signup, handle: WebAuthn::Base64Url.encode(handle))
    render json: relying_party.registration_options(
      challenge: challenge, user_handle: handle, user_name: user.email, display_name: user.display_name
    )
  end

  # Returns false (with an error on the user) if a passkey was sent but
  # doesn't verify. Without one, the account needs a password as usual.
  def attach_signup_passkey(user)
    return true if params[:passkey_credential].blank?

    state = finish_ceremony(:passkey_signup)
    registration = relying_party.verify_registration(credential_param(:passkey_credential), challenge: state["challenge"])
    user.signing_up_with_passkey = true
    user.webauthn_id = state["handle"]
    user.passkeys.build(Passkey.attributes_from(registration, name: Passkey.name_from_user_agent(request.user_agent)))
    true
  rescue WebAuthn::Error => error
    Rails.logger.info("Sign-up passkey refused: #{error.message}")
    user.errors.add(:base, "The passkey couldn't be set up. Try again, or choose a password instead.")
    false
  end

  def signup_params
    params.require(:user).permit(:display_name, :email, :password, :color)
  end
end
