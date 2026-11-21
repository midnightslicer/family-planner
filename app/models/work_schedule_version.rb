# A copy of someone's work schedule each time it's saved, so work hours in
# the past can be told apart from today's (WorkShift is only "now").
class WorkScheduleVersion < ApplicationRecord
  belongs_to :user

  def self.snapshot!(user)
    create!(user: user, effective_at: Time.current, availability: user.work_availability,
            shifts: user.work_shifts.reload.map { |s| s.slice(:weekday, :from_time, :until_time, :place) })
  end
end
