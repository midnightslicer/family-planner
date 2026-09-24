module Users
  # Second sign-in step for accounts with an authenticator app: accepts the
  # current six-digit code or one of the account's recovery codes.
  class TwoFactorController < ApplicationController
    PENDING_TTL = 10.minutes

    before_action :load_pending_user
    rate_limit to: 10, within: 10.minutes, only: :create,
               by: -> { "two-factor:#{session[:two_factor]&.fetch('user_id', nil) || request.remote_ip}" },
               with: -> {
                 session.delete(:two_factor)
                 redirect_to new_user_session_path, alert: "Too many attempts. Wait a few minutes and sign in again."
               }

    def show
    end

    def create
      if @user.verify_second_factor!(params[:code])
        session.delete(:two_factor)
        @user.remember_me = @pending["remember"]
        sign_in(:user, @user)
        redirect_to after_sign_in_path_for(@user), notice: "Signed in.", status: :see_other
      else
        flash.now[:alert] = "That code didn't work. Codes change every 30 seconds, so try the one showing now."
        render :show, status: :unprocessable_content
      end
    end

    private

    def load_pending_user
      @pending = session[:two_factor]
      if @pending.is_a?(Hash) && Time.at(@pending["at"].to_i) > PENDING_TTL.ago
        @user = User.find_by(id: @pending["user_id"])
      end
      return if @user&.two_factor_enabled?

      session.delete(:two_factor)
      redirect_to new_user_session_path, alert: "Please sign in with your password first."
    end
  end
end
