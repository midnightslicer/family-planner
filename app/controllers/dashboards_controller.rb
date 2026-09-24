class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def show
    return render(:no_household) unless current_household

    @household = current_household
    @members = @household.members_by_name
    @statuses = @household.member_statuses
    @checklist = GettingStarted.new(current_user, @household)
  end

  # POST /dashboard/dismiss_checklist
  def dismiss_checklist
    current_user.update_column(:onboarding_dismissed_at, Time.current)
    redirect_to dashboard_path, status: :see_other
  end
end
