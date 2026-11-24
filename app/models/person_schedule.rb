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
#   waiting  items others added for them that clash, awaiting their OK
#   following items they added for others with "follow up" on (only when
#            looking at their own day)
class PersonSchedule
  UPCOMING_DAYS = 14

  attr_reader :person, :now, :todos, :today, :later, :done, :at, :work, :off, :days_off, :waiting, :following

  # Everyone's schedules for the family view at once: one query for all
  # their items rather than a few per person. `members` should have their
  # work_shifts and days_off loaded (Household#board_members). Only what
  # that view shows: no waiting or following lists.
  def self.for_family(household, members, viewer:, places: household.locations.to_a, now: Time.current)
    rows = window(household.tasks, now).joins(:assignments).merge(TaskAssignment.accepted)
                                       .where(task_assignments: { user_id: members.map(&:id) })
                                       .select("tasks.*, task_assignments.user_id AS person_id")
                                       .preload(:location, :assignments).to_a
    by_person = rows.group_by(&:person_id)
    members.index_with do |member|
      new(household, member, viewer: viewer, now: now, places: places, items: by_person.fetch(member.id, []), lists: false)
    end
  end

  # Items that could be on someone's day: open ones, or finished since
  # midnight, starting before the horizon.
  def self.window(tasks, now)
    tasks.where("tasks.status IN (:open) OR tasks.finished_at >= :midnight",
                open: [Task.statuses[:planned], Task.statuses[:in_progress]], midnight: now.beginning_of_day)
         .where("tasks.starts_at IS NULL OR tasks.starts_at < :horizon", horizon: now + UPCOMING_DAYS.days)
  end

  # `viewer` sees others' private to-dos not at all, and their private
  # events only as "Busy" (the views ask Task#visible_to?). `items` and
  # `places` skip their queries when the caller has them; `lists: false`
  # skips the waiting and following lists.
  def initialize(household, person, viewer: person, now: Time.current, places: nil, items: nil, lists: true)
    @person = person
    today = now.to_date
    items ||= self.class.window(household.tasks.for_person(person), now)
                        .includes(:created_by, :location, assignments: { user: { avatar_attachment: :blob } }).to_a
    items = items.reject { |task| !task.timed? && !task.visible_to?(viewer) }

    if lists
      @waiting = household.tasks.open.for_person(person, "pending")
                          .includes(:created_by, :location, assignments: { user: { avatar_attachment: :blob } })
                          .order(:starts_at).select { |task| task.visible_to?(viewer) }
      @following = viewer == person ? following_for(household, person, now) : []
    else
      @waiting = @following = []
    end

    open, closed = items.partition(&:open?)
    @done = closed.sort_by { |task| task.finished_at || task.updated_at }.reverse
    places ||= household.locations.to_a
    @off = person.day_off_on(today)
    @days_off = person.days_off.select { |off| off.ends_on >= today && !off.covers?(today) }
    @work = WorkBlock.on(person, today, locations: places)
    midnight = now.beginning_of_day
    @today = (items.select { |task| task.timed? && task.starts_at.to_date <= today && task.finishes_at > midnight && !task.undone? } +
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

  def following_for(household, person, now)
    household.tasks.where(created_by: person, follow_up: true).where.not(id: household.tasks.for_person(person).select(:id))
             .where("status IN (:open) OR finished_at >= :midnight",
                    open: [Task.statuses[:planned], Task.statuses[:in_progress]], midnight: now.beginning_of_day)
        .includes(:created_by, :location, assignments: { user: { avatar_attachment: :blob } }).order(:created_at).to_a
  end
end
