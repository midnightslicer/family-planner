class HouseholdsController < ApplicationController
  before_action :authenticate_user!

  # POST /switch_household: validates membership, updates the session.
  def switch
    household = current_user.households.find_by(id: params[:household_id])
    if household
      session[:current_household_id] = household.id
      redirect_back(fallback_location: dashboard_path, notice: "Switched to #{household.name}.")
    else
      redirect_back(fallback_location: dashboard_path, alert: "You are not a member of that household.")
    end
  end
end
