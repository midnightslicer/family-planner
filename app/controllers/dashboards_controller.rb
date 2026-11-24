class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def show
    return render(:no_household) unless current_household

    @household = current_household
    @members = @household.board_members
    places = @household.places
    @statuses = @household.member_statuses(members: @members, places: places)
    @checklist = GettingStarted.new(current_user, @household, members: @members)
    @pets = @household.pets.here.by_name.with_attached_photo.to_a
    @pet_statuses = Pet.statuses(@household, @pets)
    @groups = @household.by_house(@members, @pets, places)
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
