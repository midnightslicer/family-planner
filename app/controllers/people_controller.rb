# A person's page is their day on the Schedule (profile, where they are,
# what they're doing); /people/:id just leads there. `locate` sets *your
# own* location: it never takes a person from params.
class PeopleController < ApplicationController
  include HouseholdScoped

  def show
    person = current_household.users.find_by(id: params[:id]) or return not_found
    redirect_to tasks_path(person: (person.id unless person == current_user))
  end

  # POST /people/me/status: the "I'm" chips on your day. Your own status
  # only (never a person from params); it wins over work and events for
  # StatusUpdate::LASTS. "clear" (tapping the lit chip again) ends it now,
  # back to what your work hours and events say.
  def set_status
    return clear_status if params[:availability] == "clear"

    update = current_user.status_updates.new(availability: params[:availability].to_s)
    message =
      if update.save
        current_user.broadcast_card
        { notice: "You're #{ScheduleHelper::AVAILABILITY.fetch(update.availability).first.downcase} until #{update.expires_at.strftime('%-l:%M %p')}." }
      else { alert: "Pick how reachable you are." }
      end
    redirect_back_or_to tasks_path, **message, status: :see_other, allow_other_host: false
  end

  def clear_status
    if (active = StatusUpdate.active_for_user(current_user))
      # History is append-only: a row that ends at once is the "cleared".
      current_user.status_updates.create!(availability: active.availability, expires_at: Time.current)
      current_user.broadcast_card
    end
    redirect_back_or_to tasks_path, notice: "Back to your schedule.", status: :see_other, allow_other_host: false
  end

  # POST /people/me/location: from the "I'm at" chips on your day (one tap,
  # including "Off property", a report with no location) or the note box
  # under them (`note`: the place you're shown at, with the note).
  def locate
    attrs = params.fetch(:location_report, {}).permit(:location_id, :new_location_name, :comment, :off_property)
    off_property = attrs[:off_property] == "1"
    location = off_property ? nil : Location.chosen(current_household, attrs[:location_id], new_name: attrs[:new_location_name], created_by: current_user)
    report = LocationReport.new(household: current_household, subject: current_user, reported_by: current_user,
                                location: location, comment: attrs[:comment], off_property: off_property)
    message =
      if report.save && params[:note] then { notice: report.comment ? "Note saved." : "Note cleared." }
      elsif report.persisted? then { notice: report.off_property? ? "You're off property." : "You're at #{report.location.name}." }
      else { alert: report.errors.full_messages.to_sentence.presence || "Pick where you are." }
      end
    redirect_back_or_to tasks_path, **message, status: :see_other, allow_other_host: false
  end
end
