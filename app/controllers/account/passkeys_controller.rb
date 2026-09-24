module Account
  class PasskeysController < BaseController
    rate_limit to: 20, within: 1.minute, only: [:options, :create], with: -> { rate_limited_json }

    # POST /account/passkeys/options: registration options for this account.
    def options
      handle = current_user.webauthn_handle
      current_user.update_column(:webauthn_id, current_user.webauthn_id) if current_user.webauthn_id_changed?
      challenge = start_ceremony(:passkey_registration)
      render json: relying_party.registration_options(
        challenge: challenge, user_handle: handle,
        user_name: current_user.email, display_name: current_user.display_name,
        exclude: current_user.passkeys.pluck(:external_id)
      )
    end

    def create
      state = finish_ceremony(:passkey_registration)
      registration = relying_party.verify_registration(credential_param, challenge: state["challenge"])
      name = params[:name].presence || Passkey.name_from_user_agent(request.user_agent)
      current_user.passkeys.create!(Passkey.attributes_from(registration, name: name))
      flash[:notice] = "Passkey added. Next time, sign in with it instead of your password."
      render json: { redirect: account_root_path }
    rescue WebAuthn::Error, ActiveRecord::RecordInvalid => error
      Rails.logger.info("Passkey registration refused: #{error.message}")
      render_json_error("That passkey couldn't be added (#{error.message}). Please try again.")
    end

    def update
      passkey = current_user.passkeys.find(params[:id])
      if passkey.update(name: params.require(:passkey)[:name])
        redirect_to account_root_path, notice: "Passkey renamed."
      else
        redirect_to account_root_path, alert: passkey.errors.full_messages.to_sentence
      end
    end

    def destroy
      passkey = current_user.passkeys.find(params[:id])
      if current_user.sign_in_methods_count <= 1
        redirect_to account_root_path, alert: "That's your only way to sign in. Set a password or add another passkey first."
      else
        passkey.destroy
        redirect_to account_root_path, notice: "Passkey removed.", status: :see_other
      end
    end
  end
end
