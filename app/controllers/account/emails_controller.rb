module Account
  # Changes the email you sign in with (and get email at). Your own only.
  class EmailsController < BaseController
    rate_limit to: 10, within: 10.minutes, only: :update, with: -> {
      redirect_to account_root_path, alert: "Too many attempts. Wait a few minutes and try again."
    }

    def update
      user = current_user
      attrs = params.require(:user).permit(:email, :current_password)
      if user.change_email(attrs[:email], current_password: attrs[:current_password])
        redirect_to account_root_path, notice: "Email changed to #{user.email}."
      else
        load_account_page
        @user = user
        @email_errors = true
        render "account/profiles/show", status: :unprocessable_content
      end
    end
  end
end
