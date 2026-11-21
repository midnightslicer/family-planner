# A schedule item. Two shapes:
#
# - a to-do: no time. Stays on the person's running list until done or
#   skipped; `due_on` optionally holds it back until a given day.
# - an event: `starts_at`..`ends_at` (an end is always set; one hour if none
#   was given), maybe a `place`. While it's on, the person's card shows it
#   automatically: no need to press Start.
#
# `availability` says how reachable they are meanwhile: free (call any
# time), text (busy, but a text is fine) or busy (do not disturb).
class Task < ApplicationRecord
  DEFAULT_LENGTH = 1.hour

  belongs_to :household
  # Who it's for (TaskAssignment): accepted, pending (it clashed with their
  # schedule) or declined. No one at all means it's for anyone.
  has_many :assignments, -> { order(:id) }, class_name: "TaskAssignment", inverse_of: :task, dependent: :delete_all
  belongs_to :created_by, class_name: "User", optional: true
  # Who ticked it off or skipped it (Current.user at the time).
  belongs_to :finished_by, class_name: "User", optional: true
  # Set from `place` when it names one of the household's locations: while
  # the event is on, that's where the person is (see #whereabouts).
  belongs_to :location, optional: true

  enum :status, { planned: 0, in_progress: 1, undone: 2, completed: 3 }
  enum :availability, { free: "free", text: "text", busy: "busy" }, prefix: :availability
  enum :recurrence_interval, { no_recurrence: "", daily: "daily", weekly: "weekly", biweekly: "biweekly", monthly: "monthly" },
       prefix: :recurs

  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2_000 }
  validates :place, length: { maximum: 60 }
  validate :ends_after_start
  validates :recurrence_interval, inclusion: { in: recurrence_intervals.keys }

  # Live updates: every change re-renders the affected person cards on the
  # household's dashboards and wall, and pings the assignee's browser when
  # someone else touched their task.
  after_commit :broadcast_member_cards
  after_commit :notify_people, on: :update

  # The planned copy a recurring task spawns; its assignee already heard
  # about the task being finished, so it doesn't notify again.
  attr_accessor :recurrence_copy

  # The schedule form's fields: a day, and optionally a from/until time on
  # it. Without a time it's a to-do (for that day, if one was given). Set
  # `schedule_fields` to apply them; other callers set the columns directly.
  attr_accessor :on_date, :from_time, :until_time, :schedule_fields
  before_validation :apply_schedule_fields, if: :schedule_fields

  normalizes :place, with: ->(place) { place.squish.presence }
  before_validation :link_location

  STATUS_VERBS = { "in_progress" => "started", "planned" => "paused", "completed" => "finished", "undone" => "skipped" }.freeze

  scope :for_household, ->(household) { where(household_id: household.id) }
  # Items on `user`'s schedule (or, with status "pending", waiting for their OK).
  scope :for_person, ->(user, status = "accepted") {
    where(id: TaskAssignment.where(user_id: user.id, status: status).select(:task_id))
  }
  # Items nobody has taken: for anyone.
  scope :for_anyone, -> { where.not(id: TaskAssignment.active.select(:task_id)) }
  scope :open, -> { where(status: [:planned, :in_progress]) }
  scope :timed, -> { where.not(starts_at: nil) }
  scope :untimed, -> { where(starts_at: nil) }

  def timed?
    starts_at.present?
  end

  def work? = false

  # Private items show their details only to whoever they're for and
  # whoever added them; everyone else sees "Busy". A nil viewer (the public
  # wall, live broadcasts) never sees them.
  def visible_to?(user)
    !private? || (user.present? && (created_by_id == user.id || assignment_for(user)&.then { |a| !a.declined? }))
  end

  def assignment_for(user)
    user && assignments.find { |assignment| assignment.user_id == user.id }
  end

  # The people it's on the schedule of.
  def people
    assignments.select(&:accepted?).map(&:user)
  end

  # Everyone it's for who hasn't declined (accepted and waiting).
  def active_assignments
    assignments.reject(&:declined?)
  end

  # Shorthand for one person who has it on their schedule, as when adding
  # something for yourself: `Task.create!(assigned_to: user, ...)`.
  def assigned_to=(user)
    assignments.build(user: user, status: "accepted") if user
  end

  def assigned_to
    people.first
  end

  # Whoever added it, anyone it's for, or an admin.
  def editable_by?(user)
    return false if user.nil?

    created_by_id == user.id || assignment_for(user)&.then { |a| !a.declined? } || user.admin?
  end

  def title_for(user)
    visible_to?(user) ? title : "Busy"
  end

  # The place to show: the linked location's current name, else what was typed.
  def place_name
    location&.name || place
  end

  # Where an event puts its person while it's on: its linked location, if
  # it's on now and not private.
  def whereabouts(time = Time.current)
    location if location && !private? && happening_at?(time)
  end

  def open?
    planned? || in_progress?
  end

  # Older events may lack an end; treat them as an hour long.
  def finishes_at
    ends_at || (starts_at && starts_at + DEFAULT_LENGTH)
  end

  def happening_at?(time = Time.current)
    timed? && open? && starts_at <= time && time < finishes_at
  end

  def past?(time = Time.current)
    timed? && finishes_at <= time
  end

  # A to-do held back for a later day.
  def later?(today = Date.current)
    due_on.present? && due_on > today
  end

  # A timed recurring event that has ended without anyone marking it: mark
  # it done and schedule the next one (catching up on missed repeats), so
  # "Church every Sunday" keeps coming round by itself. Quietly: nobody
  # needs a notification for this.
  def roll_forward!(now = Time.current)
    task = self
    12.times do
      break unless task.planned? && task.timed? && task.send(:recurs?) && task.finishes_at <= now

      task.recurrence_copy = true
      task.update!(status: :completed, finished_at: task.finishes_at) # it ended when it ended
      task = task.send(:schedule_next_occurrence) or break
    end
  end

  # Transitions: planned→in_progress ("Start"), undone→in_progress (restart a
  # cancelled one-off), in_progress→planned ("Pause"), planned or
  # in_progress→completed (ticking off a to-do needn't start it first),
  # planned or in_progress→undone ("Skip"). Any other transition is ignored
  # (false).
  def start!
    return false unless planned? || restartable?

    update!(status: :in_progress, started_at: Time.current, finished_at: nil, finished_by: nil)
    true
  end

  # Keeps started_at, so the card can still say since when.
  def pause!
    return false unless in_progress?

    update!(status: :planned)
    true
  end

  def complete!
    return false unless open?

    update!(status: :completed, finished_at: Time.current, finished_by: Current.user)
    schedule_next_occurrence
    true
  end

  def cancel!
    return false unless open?

    update!(status: :undone, finished_at: Time.current, finished_by: Current.user)
    schedule_next_occurrence
    true
  end

  # A cancelled recurring task already spawned its next copy on cancel, so
  # restarting it would schedule a duplicate; only one-offs come back.
  def restartable?
    undone? && !recurs?
  end

  private

  # On finishing/skipping a recurring item, create its next planned copy,
  # then clear next_occurrence on this finished instance. Events move their
  # time along; to-dos come back on the next day/week/month (due_on).
  # Returns the copy.
  def schedule_next_occurrence
    return unless recurs?

    attributes = { recurrence_copy: true, household: household, title: title, description: description, private: private?,
                   created_by: created_by, recurrence_interval: recurrence_interval, follow_up: follow_up,
                   availability: availability, place: place }
    if timed?
      new_starts_at = next_start_from(starts_at) or return
      attributes.merge!(starts_at: new_starts_at, ends_at: ends_at&.then { |e| e + (new_starts_at - starts_at) })
    else
      base = [due_on, Date.current].compact.max
      attributes[:due_on] = next_start_from(base.in_time_zone).to_date
    end

    # Whoever had agreed to it has the next one too.
    copy = Task.new(attributes)
    people.each { |person| copy.assignments.build(user: person, status: "accepted") }
    copy.save!
    update_column(:next_occurrence, nil)
    copy
  end

  def link_location
    return unless will_save_change_to_place? || new_record?

    self.location = place && household && household.locations.where("lower(name) = ?", place.downcase).first
  end

  def apply_schedule_fields
    day = Date.iso8601(on_date.to_s) if on_date.present?
    if from_time.present?
      day ||= Date.current
      self.starts_at = Time.zone.parse("#{day.iso8601} #{from_time}")
      finish = Time.zone.parse("#{day.iso8601} #{until_time}") if until_time.present?
      finish += 1.day if finish && finish <= starts_at # e.g. 10pm until 1am
      self.ends_at = finish || starts_at + DEFAULT_LENGTH
      self.due_on = nil
    else
      self.starts_at = nil
      self.ends_at = nil
      self.due_on = day
    end
  rescue Date::Error, ArgumentError
    errors.add(:base, "That date or time didn't make sense.")
  end

  def next_start_from(base)
    base = Time.current if base.nil?
    case recurrence_interval
    when "daily" then base + 1.day
    when "weekly" then base + 7.days
    when "biweekly" then base + 14.days
    when "monthly" then next_month_from(base)
    end
  end

  # One month ahead, clamping the day to the target month's length.
  def next_month_from(base)
    next_month = base.to_date >> 1
    last_day = Date.new(next_month.year, next_month.month, -1).day
    day = [base.day, last_day].min
    Time.zone.local(next_month.year, next_month.month, day, base.hour, base.min, base.sec)
  end

  # recurrence_interval returns the enum key, so the "" member reads back as
  # "no_recurrence" and is always present? — ask the enum instead.
  def recurs?
    !recurs_no_recurrence?
  end

  def ends_after_start
    return if starts_at.blank? || ends_at.blank? || ends_at >= starts_at

    errors.add(:ends_at, "must be after the start time")
  end

  def broadcast_member_cards
    return if destroyed_by_association

    household&.broadcast_member_cards(assignments.map(&:user_id).uniq)
  rescue StandardError => error
    Rails.logger.warn("Live update failed for task #{id}: #{error.class}: #{error.message}")
  end

  # When someone starts, finishes or skips an item, the others it's for
  # (and its creator, if they asked to follow up) hear about it.
  def notify_people
    actor = Current.user
    return if recurrence_copy || actor.nil? || !saved_change_to_status?

    recipients = people
    recipients += [created_by] if follow_up? && created_by
    message = "#{actor.display_name} #{STATUS_VERBS.fetch(status, 'updated')} #{title}"
    recipients.compact.uniq.reject { |person| person == actor }.each do |person|
      Turbo::StreamsChannel.broadcast_append_to(
        person, :notifications,
        target: "notifications", partial: "shared/notification",
        locals: { title: household.name, body: message, tag: "task-#{id}" }
      )
    end
  rescue StandardError => error
    Rails.logger.warn("Notification failed for task #{id}: #{error.class}: #{error.message}")
  end
end
