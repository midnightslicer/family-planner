# Saves the profile form, for yourself (account page) or, by an admin, for
# someone else (their Manage profile page): name, color, photo,
# birthday, and the house they live in within `household` (one of its
# houses, nothing, or a new house typed right there).
class ProfileUpdate
  PERMITTED = [:display_name, :color, :custom_color, :avatar, :remove_avatar, :birthday].freeze

  attr_reader :user

  def initialize(user, household:, params:)
    @user = user
    @household = household
    @params = params
  end

  def save
    saved = User.transaction do
      (user.update(@params.require(:user).permit(*PERMITTED)) && save_home) || raise(ActiveRecord::Rollback)
    end
    return false unless saved

    user.broadcast_card
    @household&.broadcast_refresh
    true
  end

  private

  def save_home
    return true unless @household && @params.key?(:home_id)

    membership = user.household_memberships.find_by!(household: @household)
    home = @params[:home_id].blank? ? nil :
      Location.chosen(@household, @params[:home_id], new_name: @params[:new_home_name], kind: "house", created_by: user)
    if home&.new_record? && !home.save
      home.errors.each { |error| user.errors.add(:base, "New house #{error.message}") }
      return false
    end
    return true if membership.update(home: home)

    membership.errors.each { |error| user.errors.add(:base, error.full_message) }
    false
  end
end
