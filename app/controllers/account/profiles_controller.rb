module Account
  # The account page: profile, sign-in methods (password, passkeys) and
  # two-factor authentication, for every member.
  class ProfilesController < BaseController
    before_action :load_account_page

    def show
    end

    def update
      if @user.update(profile_params)
        @user.broadcast_card
        redirect_to account_root_path, notice: "Profile saved."
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    def profile_params
      params.require(:user).permit(:display_name, :handle, :color, :custom_color, :avatar, :remove_avatar)
    end
  end
end
