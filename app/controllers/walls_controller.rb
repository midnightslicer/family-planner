# Public household wall (kiosk view) — no auth; scoped by the household's
# unguessable dashboard token. Invalid token → 404. Renders the identical
# card partial used by the authenticated dashboard, in the kiosk layout.
class WallsController < ApplicationController
  skip_before_action :configure_first_run_gate, only: [:show]

  def show
    @household = Household.find_by!(dashboard_token: params[:dashboard_token])
    @members = @household.members_by_name
    render layout: "wall"
  rescue ActiveRecord::RecordNotFound
    raise ActionController::RoutingError.new("Not Found")
  end
end