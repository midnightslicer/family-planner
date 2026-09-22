class DashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_household!

  def show
    @household = current_household
    @members = @household.members_by_name
  end

  private

  def require_household!
    redirect_to(new_user_session_path) unless current_user&.households.any?
  end
end