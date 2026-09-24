module Users
  # Password sign-in. People with two-factor authentication on stop after the
  # password check and finish at Users::TwoFactorController; they are not
  # signed in until the code is accepted.
  class SessionsController < Devise::SessionsController
    # Devise turns on params authentication for #create before any other
    # filter runs, so anything that calls `current_user` first would run
    # Warden's password strategy and sign the person in before we get to
    # check for two-factor. Keep the context lookup out of this request.
    skip_before_action :set_current_context, only: :create

    rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
      redirect_to new_user_session_path, alert: "Too many sign-in attempts. Wait a few minutes and try again."
    }

    def create
      user = User.find_for_authentication(email: sign_in_params[:email].to_s)
      if user&.two_factor_enabled? && user.valid_password?(sign_in_params[:password].to_s) && user.active_for_authentication?
        session[:two_factor] = {
          "user_id" => user.id,
          "remember" => ActiveModel::Type::Boolean.new.cast(sign_in_params[:remember_me]),
          "at" => Time.current.to_i
        }
        redirect_to user_two_factor_path, status: :see_other
      else
        super
      end
    end
  end
end
