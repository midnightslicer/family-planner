class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def show
    return render(:no_household) unless current_household

    @household = current_household
    @members = @household.members_by_name
    @statuses = @household.member_statuses
    @checklist = GettingStarted.new(current_user, @household)
    @pets = @household.pets.here.by_name.with_attached_photo
    @pet_statuses = Pet.statuses(@household, @pets)
  end

  # POST /dashboard/dismiss_checklist
  def dismiss_checklist
    current_user.update_column(:onboarding_dismissed_at, Time.current)
    redirect_to dashboard_path, status: :see_other
  end

  # POST /getting_started/skip/:step ("I don't have a work schedule").
  def skip_step
    case params[:step]
    when "work" then current_user.update_column(:work_schedule_skipped_at, Time.current)
    else return head(:not_found)
    end
    redirect_back_or_to dashboard_path, status: :see_other
  end
end
