module Account
  # Issues a fresh set of recovery codes (the old ones stop working). Asks
  # for a current code first, since the new codes are shown on screen.
  class RecoveryCodesController < BaseController
    rate_limit to: 10, within: 10.minutes, only: :create, with: -> {
      redirect_to account_root_path, alert: "Too many attempts. Wait a few minutes and try again."
    }

    def create
      if current_user.verify_second_factor!(params[:code])
        @recovery_codes = current_user.regenerate_recovery_codes!
        render :show
      else
        redirect_to account_root_path, alert: "That code didn't match, so your recovery codes were not changed."
      end
    end
  end
end
