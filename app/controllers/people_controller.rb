# A person's page is their day on the Schedule (profile, where they are,
# what they're doing); /people/:id just leads there. `locate` sets *your
# own* location: it never takes a person from params.
class PeopleController < ApplicationController
  include HouseholdScoped

  def show
    person = current_household.users.find_by(id: params[:id]) or return head(:not_found)
    redirect_to tasks_path(person: (person.id unless person == current_user))
  end

  # POST /people/me/location: from the "I'm at" chips on your day (one tap)
  # or the fuller form under them (a comment, or a new place).
  def locate
    attrs = params.fetch(:location_report, {}).permit(:location_id, :new_location_name, :comment)
    location = Location.chosen(current_household, attrs[:location_id], new_name: attrs[:new_location_name], created_by: current_user)
    report = LocationReport.new(household: current_household, subject: current_user, reported_by: current_user,
                                location: location, comment: attrs[:comment])
    message =
      if report.save then { notice: "You're at #{report.location.name}." }
      else { alert: report.errors.full_messages.to_sentence.presence || "Pick where you are." }
      end
    redirect_back_or_to tasks_path, **message, status: :see_other, allow_other_host: false
  end
end
