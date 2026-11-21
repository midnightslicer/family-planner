# Every minute (config/recurring.yml): moves finished recurring events on,
# and refreshes the boards of households where an event just started or
# ended, so cards flip to "In a meeting" and back without anyone touching
# anything.
class ScheduleTickJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current, window = 70.seconds)
    Household.find_each { |household| household.roll_recurring_events!(now) }

    edges = Task.open.timed.where(starts_at: (now - window)..now)
                .or(Task.open.timed.where(ends_at: (now - window)..now))
    Household.where(id: edges.select(:household_id)).find_each(&:broadcast_refresh)
  end
end
