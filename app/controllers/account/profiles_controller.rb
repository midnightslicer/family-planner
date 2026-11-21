module Account
  # The account page: profile, sign-in methods (password, passkeys) and
  # two-factor authentication, for every member.
  class ProfilesController < BaseController
    before_action :load_account_page

    def show
    end

    def update
      saved = User.transaction do
        (@user.update(profile_params) && save_home) || raise(ActiveRecord::Rollback)
      end
      if saved
        @user.broadcast_card
        current_household&.broadcast_refresh
        redirect_to account_root_path, notice: "Profile saved."
      else
        render :show, status: :unprocessable_content
      end
    end

    private

    # "I live at": one of the current household's houses, nothing, or a new
    # house typed right there (as on the pet form).
    def save_home
      return true unless current_household && params.key?(:home_id)

      membership = @user.household_memberships.find_by!(household: current_household)
      home = params[:home_id].blank? ? nil :
        Location.chosen(current_household, params[:home_id], new_name: params[:new_home_name], kind: "house", created_by: @user)
      if home&.new_record? && !home.save
        home.errors.each { |error| @user.errors.add(:base, "New house #{error.message}") }
        return false
      end
      membership.update(home: home) || (membership.errors.each { |error| @user.errors.add(:base, error.full_message) } && false)
    end

    def profile_params
      params.require(:user).permit(:display_name, :handle, :color, :custom_color, :avatar, :remove_avatar, :birthday)
    end
  end
end
