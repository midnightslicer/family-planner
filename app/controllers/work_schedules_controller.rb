# Your regular work hours: which weekdays, from/until, where (remote, an
# office...), and how reachable you are while working. Optional: with no
# days ticked you simply have no work hours.
class WorkSchedulesController < ApplicationController
  include HouseholdScoped
  include ManagesPerson

  before_action :require_managed_person

  WEEK = [1, 2, 3, 4, 5, 6, 0].freeze # Monday first

  def edit
    load_page
  end

  def update
    days = params.dig(:work_schedule, :days)&.to_unsafe_h || {}
    managed_person.work_availability = params.dig(:work_schedule, :availability).presence || managed_person.work_availability
    errors = []
    WorkShift.transaction do
      managed_person.save!
      WEEK.each do |weekday|
        day = days.fetch(weekday.to_s, {})
        shift = managed_person.work_shifts.find_or_initialize_by(weekday: weekday)
        if day["on"] == "1"
          place = day["place"] == Location::NEW ? day["place_other"] : day["place"]
          shift.assign_attributes(from_time: day["from_time"], until_time: day["until_time"], place: place)
          errors.concat(shift.errors.full_messages.map { |m| "#{Date::DAYNAMES[weekday]}: #{m}" }) unless shift.save
        elsif shift.persisted?
          shift.destroy!
        end
      end
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.empty?
      announce_change
      redirect_to edit_work_schedule_path(**managed_person_param), notice: managed_person.work_shifts.reload.any? ? "Work schedule saved." : "No work hours set.", status: :see_other
    else
      flash.now[:alert] = errors.to_sentence
      load_page
      render :edit, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordInvalid => error
    flash.now[:alert] = error.record.errors.full_messages.to_sentence
    load_page
    render :edit, status: :unprocessable_content
  end

  private

  def load_page
    @shifts = managed_person.work_shifts.reload.index_by(&:weekday)
    @days_off = managed_person.days_off.upcoming
    @locations = current_household.locations.in_display_order
  end

  def announce_change
    announce_change_for(managed_person)
  end
end
