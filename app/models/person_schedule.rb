# One person's schedule as the Schedule page shows it, loaded in one query:
#
#   now     what they're doing (an event in progress, else a started to-do)
#   todos   their running to-do list: open, untimed, due by today
#   today   today's events, past ones included (shown dimmed)
#   later   events after today and to-dos held for a later day
#   done    what they finished or skipped today
#   at      the location their current event puts them at, if any
#   work    today's work hours (a WorkBlock), unless they're off
#   off     today's DayOff, if they're off
#   days_off coming days off
class PersonSchedule
  UPCOMING_DAYS = 14

  attr_reader :person, :now, :todos, :today, :later, :done, :at, :work, :off, :days_off

  # `viewer` sees others' private to-dos not at all, and their private
  # events only as "Busy" (the views ask Task#visible_to?).
  def initialize(household, person, viewer: person, now: Time.current)
    @person = person
    today = now.to_date
    items = household.tasks.where(assigned_to: person).includes(:created_by, :location)
                     .where("status IN (:open) OR updated_at >= :midnight", open: open_statuses, midnight: now.beginning_of_day)
                     .where("starts_at IS NULL OR starts_at < :horizon", horizon: now + UPCOMING_DAYS.days)
                     .to_a
    items.reject! { |task| !task.timed? && !task.visible_to?(viewer) }

    open, closed = items.partition(&:open?)
    @done = closed.sort_by(&:updated_at).reverse
    places = household.locations.to_a
    @off = person.day_off_on(today)
    @days_off = person.days_off.select { |off| off.ends_on >= today && !off.covers?(today) }
    @work = WorkBlock.on(person, today, locations: places)
    @today = (items.select { |task| task.timed? && task.starts_at.to_date <= today && task.finishes_at > now.beginning_of_day && !task.undone? } +
              [@work].compact).sort_by(&:starts_at)
    @now = open.find { |task| task.happening_at?(now) } || open.find(&:in_progress?) ||
           WorkBlock.current(person, now, locations: places)
    @at = @now&.whereabouts(now)
    @todos = open.reject(&:timed?).reject { |task| task.later?(today) }
                 .sort_by { |task| [task.in_progress? ? 0 : 1, task.due_on || Date.new(9999), task.created_at] }
    @later = open.select { |task| task.timed? ? task.starts_at.to_date > today : task.later?(today) }
                 .sort_by { |task| task.timed? ? task.starts_at : task.due_on.in_time_zone }
  end

  private

  def open_statuses
    [Task.statuses[:planned], Task.statuses[:in_progress]]
  end
end
