module Users
  # Passkey sign-in. The browser offers any passkey it holds for this site
  # (from the email field's autofill or the "Sign in with a passkey" button),
  # and the signature it returns is checked against the stored public key.
  # A passkey already combines the device with a PIN or biometric, so it
  # doesn't also ask for an authenticator code.
  class PasskeySessionsController < ApplicationController
    rate_limit to: 30, within: 1.minute, with: -> { rate_limited_json }

    def options
      challenge = start_ceremony(:passkey_login)
      render json: relying_party.authentication_options(challenge: challenge)
    end

    def create
      state = finish_ceremony(:passkey_login)
      credential = credential_param
      passkey = Passkey.includes(:user).find_by(external_id: credential["id"].to_s)
      raise WebAuthn::Error, "unknown passkey" unless passkey

      user = passkey.user
      handle = credential.dig("response", "userHandle")
      raise WebAuthn::Error, "user handle mismatch" if handle.present? && handle != user.webauthn_id

      count = relying_party.verify_authentication(
        credential, challenge: state["challenge"],
        public_key: passkey.public_key, algorithm: passkey.algorithm, sign_count: passkey.sign_count
      )
      raise WebAuthn::Error, "account inactive" unless user.active_for_authentication?

      passkey.update!(sign_count: count, last_used_at: Time.current)
      user.remember_me = true
      sign_in(:user, user)
      render json: { redirect: after_sign_in_path_for(user) }
    rescue WebAuthn::Error => error
      Rails.logger.info("Passkey sign-in refused: #{error.message}")
      render_json_error("That passkey didn't work here. If it was removed from your account, sign in with your password.")
    end
  end
end
