module Account
  # Changes the password (asking for the current one), or sets a first one
  # for accounts created with a passkey.
  class PasswordsController < BaseController
    rate_limit to: 10, within: 10.minutes, only: :update, with: -> {
      redirect_to account_root_path, alert: "Too many attempts. Wait a few minutes and try again."
    }

    def update
      @user = current_user
      had_password = @user.password_set?
      saved =
        if had_password
          @user.update_with_password(params.require(:user).permit(:current_password, :password))
        else
          @user.update(params.require(:user).permit(:password))
        end

      if saved
        # Changing the password rotates the session salt; stay signed in here.
        bypass_sign_in(@user)
        redirect_to account_root_path, notice: had_password ? "Password changed." : "Password set."
      else
        load_account_page
        @user = current_user
        render "account/profiles/show", status: :unprocessable_content
      end
    end
  end
end
