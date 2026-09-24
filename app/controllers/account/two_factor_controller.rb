module Account
  # Turns authenticator-app (TOTP) two-factor authentication on and off.
  class TwoFactorController < BaseController
    rate_limit to: 10, within: 10.minutes, only: [:create, :destroy], with: -> {
      redirect_to account_root_path, alert: "Too many attempts. Wait a few minutes and try again."
    }

    def new
      return redirect_to(account_root_path, notice: "Two-step verification is already on.") if current_user.two_factor_enabled?

      # Kept in the (encrypted) session until confirmed, so reloading the page
      # doesn't invalidate a code someone already scanned.
      session[:pending_otp_secret] ||= Totp.random_secret
      load_setup
    end

    def create
      secret = session[:pending_otp_secret]
      return redirect_to(new_account_two_factor_path) if secret.blank?

      if (@recovery_codes = current_user.enable_two_factor!(secret, params[:code]))
        session.delete(:pending_otp_secret)
        flash.now[:notice] = "Two-step verification is on."
        render "account/recovery_codes/show"
      else
        flash.now[:alert] = "That code didn't match. Check the time on your phone is set automatically, then try the current code."
        load_setup
        render :new, status: :unprocessable_content
      end
    end

    def destroy
      if current_user.verify_second_factor!(params[:code])
        current_user.disable_two_factor!
        redirect_to account_root_path, notice: "Two-step verification is off.", status: :see_other
      else
        redirect_to account_root_path, alert: "That code didn't match, so two-step verification is still on."
      end
    end

    private

    def load_setup
      @secret = session[:pending_otp_secret]
      @uri = Totp.provisioning_uri(@secret, account: current_user.email, issuer: app_name)
      @qr_svg = QrCode.new(@uri).to_svg(label: "QR code for your authenticator app")
    end
  end
end
