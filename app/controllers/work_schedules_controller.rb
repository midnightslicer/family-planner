# Your regular work hours: which weekdays, from/until, where (remote, an
# office...), and how reachable you are while working. Optional: with no
# days ticked you simply have no work hours.
class WorkSchedulesController < ApplicationController
  include HouseholdScoped

  WEEK = [1, 2, 3, 4, 5, 6, 0].freeze # Monday first

  def edit
    load_page
  end

  def update
    days = params.dig(:work_schedule, :days)&.to_unsafe_h || {}
    current_user.work_availability = params.dig(:work_schedule, :availability).presence || current_user.work_availability
    errors = []
    WorkShift.transaction do
      current_user.save!
      WEEK.each do |weekday|
        day = days.fetch(weekday.to_s, {})
        shift = current_user.work_shifts.find_or_initialize_by(weekday: weekday)
        if day["on"] == "1"
          shift.assign_attributes(from_time: day["from_time"], until_time: day["until_time"], place: day["place"])
          errors.concat(shift.errors.full_messages.map { |m| "#{Date::DAYNAMES[weekday]}: #{m}" }) unless shift.save
        elsif shift.persisted?
          shift.destroy!
        end
      end
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.empty?
      announce_change
      redirect_to edit_work_schedule_path, notice: current_user.work_shifts.reload.any? ? "Work schedule saved." : "No work hours set.", status: :see_other
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
    @shifts = current_user.work_shifts.reload.index_by(&:weekday)
    @days_off = current_user.days_off.upcoming
    @locations = current_household.locations.in_display_order
  end

  def announce_change
    current_user.broadcast_card
    current_user.households.each(&:broadcast_refresh)
  end
end
