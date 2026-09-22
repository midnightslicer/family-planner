module Admin
  class ProfilesController < BaseController
    def edit
      @user = current_user
    end

    def update
      @user = current_user
      if @user.update(profile_params)
        redirect_to admin_profile_path, notice: "Profile updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def profile_params
      params.require(:user).permit(:display_name, :color)
    end
  end
end