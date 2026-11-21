# A household member's profile: photo, birthday, where they are. Only the
# person themselves can say where they are (`locate` never takes a person
# from params).
class PeopleController < ApplicationController
  include HouseholdScoped

  HISTORY_LIMIT = 10

  def show
    @person = current_household.users.find_by(id: params[:id]) or return head(:not_found)
    @status = current_household.member_statuses[@person.id]
    @history = current_household.location_reports.where(subject: @person).recent.limit(HISTORY_LIMIT)
    if @person == current_user
      @report = LocationReport.new(location_id: @status[:location]&.location_id)
      @locations = current_household.locations.in_display_order.with_attached_photo
    end
  end

  # POST /people/me/location
  def locate
    attrs = params.fetch(:location_report, {}).permit(:location_id, :new_location_name, :comment)
    location = Location.chosen(current_household, attrs[:location_id], new_name: attrs[:new_location_name], created_by: current_user)
    @report = LocationReport.new(household: current_household, subject: current_user, reported_by: current_user,
                                 location: location, comment: attrs[:comment])
    @new_location_name = attrs[:new_location_name]
    if @report.save
      redirect_to person_path(current_user), notice: "You're at #{@report.location.name}.", status: :see_other
    else
      @person = current_user
      @status = current_household.member_statuses[@person.id]
      @history = current_household.location_reports.where(subject: @person).recent.limit(HISTORY_LIMIT)
      @locations = current_household.locations.in_display_order.with_attached_photo
      render :show, status: :unprocessable_content
    end
  end
end
