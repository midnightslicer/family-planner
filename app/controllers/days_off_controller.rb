# Days off: one tap for today (from your day), or a range with a note
# (from the work schedule page). Your own, or anyone's for an admin
# (ManagesPerson).
class DaysOffController < ApplicationController
  include HouseholdScoped
  include ManagesPerson

  before_action :require_managed_person

  def create
    attrs = params.fetch(:day_off, {}).permit(:starts_on, :ends_on, :note)
    attrs[:starts_on] = Date.current if params[:today] || attrs[:starts_on].blank?
    attrs[:ends_on] = attrs[:starts_on] if attrs[:ends_on].blank?
    day_off = managed_person.days_off.new(attrs)
    message =
      if day_off.save
        announce_change
        notice =
          if day_off.single_day? && day_off.starts_on == Date.current && !managing_someone_else? then "You're off today. Enjoy it."
          elsif day_off.single_day? then "Day off on #{helpers.day_name(day_off.starts_on)}."
          else "Days off saved."
          end
        { notice: notice }
      else
        { alert: day_off.errors.full_messages.to_sentence }
      end
    redirect_back_or_to edit_work_schedule_path(**managed_person_param), **message, status: :see_other, allow_other_host: false
  end

  # DELETE /days_off/:id: "I'm working after all", or a cancelled holiday.
  def destroy
    day_off = managed_person.days_off.find_by(id: params[:id]) or return not_found
    day_off.destroy
    announce_change
    redirect_back_or_to edit_work_schedule_path(**managed_person_param), notice: "Day off removed.", status: :see_other, allow_other_host: false
  end

  private

  def announce_change
    announce_change_for(managed_person)
  end
end
