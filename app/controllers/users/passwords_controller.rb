module Users
  # Devise's password reset, rate limited so the form can't be used to flood
  # someone's inbox.
  class PasswordsController < Devise::PasswordsController
    rate_limit to: 5, within: 15.minutes, only: :create, with: -> {
      redirect_to new_user_password_path, alert: "Too many reset requests. Wait a few minutes and try again."
    }
  end
end
