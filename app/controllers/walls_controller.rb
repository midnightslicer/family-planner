# The household wall (kiosk view) for a wall-mounted tablet. It shows where
# everyone is, so it needs a signed-in member of the household: the token in
# the URL only says which household's wall, and is no credential. A
# wall-mounted tablet stays signed in (remember-me), and signing in sends you
# back here. Not a member, or an unknown token -> 404.
class WallsController < ApplicationController
  before_action :authenticate_user!

  def show
    @household = wall_household
    raise ActionController::RoutingError, "Not Found" unless @household

    @members = @household.members_by_name
    @statuses = @household.member_statuses
    @pets = @household.pets.here.by_name.with_attached_photo
    @pet_statuses = Pet.statuses(@household, @pets)
    @sections = Whereabouts.new(@household, members: @members.with_attached_avatar, statuses: @statuses,
                                            pets: @pets, pet_statuses: @pet_statuses).sections
    render layout: "wall"
  end

  private

  def wall_household
    return @wall_household if defined?(@wall_household)

    @wall_household = current_user&.households&.find_by(dashboard_token: params[:dashboard_token].to_s)
  end

  # The wall runs on its household's clock too.
  def time_zone_household
    wall_household
  end

  def kiosk?
    true
  end
end
