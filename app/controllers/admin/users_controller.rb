module Admin
  # Everyone with an account: make or unmake admins, help someone who lost
  # their phone back in, or delete an account.
  class UsersController < BaseController
    before_action :set_user, except: :index
    before_action :protect_self, only: [:update, :destroy]

    def index
      @users = User.includes(:households).order(:display_name)
      @passkey_counts = Passkey.group(:user_id).count
    end

    def update
      @user.update!(admin: params.require(:user)[:admin] == "1")
      redirect_to admin_users_path, notice: "#{@user.display_name} is #{@user.admin? ? 'now' : 'no longer'} an admin."
    end

    def reset_security
      @user.reset_sign_in_security!
      message = "Removed #{@user.display_name}'s passkeys and two-step verification."
      message += @user.password_set? ? " They can sign in with their password, or reset it from the sign-in page." : " They'll need to reset their password from the sign-in page."
      redirect_to admin_users_path, notice: message
    end

    # Shows a one-time password reset link to pass on by hand.
    def password_link
      @reset_url = edit_user_password_url(reset_password_token: @user.generate_password_reset_token!, **AppSettings.url_options)
    end

    def destroy
      @user.destroy
      redirect_to admin_users_path, notice: "#{@user.display_name}'s account was deleted.", status: :see_other
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def protect_self
      redirect_to admin_users_path, alert: "You can't change or delete your own admin account here." if @user == current_user
    end
  end
end
