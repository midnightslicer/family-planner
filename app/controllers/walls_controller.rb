# Public household wall (kiosk view): no sign-in; the household's secret
# dashboard token in the URL is the credential. Invalid token -> 404.
class WallsController < ApplicationController
  skip_before_action :require_setup
  # Lets the wall be embedded in a home dashboard (Home Assistant, a browser
  # start page...). It's read-only, so framing can't be abused for clicks.
  content_security_policy { |policy| policy.frame_ancestors "*" }
  after_action { response.headers.delete("X-Frame-Options") }

  def show
    @household = Household.find_by(dashboard_token: params[:dashboard_token].to_s)
    raise ActionController::RoutingError, "Not Found" unless @household

    @members = @household.members_by_name
    @statuses = @household.member_statuses
    render layout: "wall"
  end

  private

  def kiosk?
    true
  end
end
