# Public household wall (kiosk view): no sign-in; the household's secret
# dashboard token in the URL is the credential. Invalid token -> 404.
class WallsController < ApplicationController
  skip_before_action :require_setup
  # Lets the wall be embedded in a home dashboard (Home Assistant, a browser
  # start page...). It's read-only, so framing can't be abused for clicks.
  content_security_policy { |policy| policy.frame_ancestors "*" }
  after_action { response.headers.delete("X-Frame-Options") }

  def show
    @household = wall_household
    raise ActionController::RoutingError, "Not Found" unless @household

    @members = @household.members_by_name
    @statuses = @household.member_statuses
    @pets = @household.pets.by_name.with_attached_photo
    @pet_statuses = Pet.statuses(@household, @pets)
    @sections = Whereabouts.new(@household, members: @members.with_attached_avatar, statuses: @statuses,
                                            pets: @pets, pet_statuses: @pet_statuses).sections
    render layout: "wall"
  end

  private

  def wall_household
    return @wall_household if defined?(@wall_household)

    @wall_household = Household.find_by(dashboard_token: params[:dashboard_token].to_s)
  end

  # The wall runs on its household's clock too.
  def time_zone_household
    wall_household
  end

  def kiosk?
    true
  end
end
