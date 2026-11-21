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
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :status, { planned: 0, in_progress: 1, undone: 2, completed: 3 }
  enum :availability, { free: "free", text: "text", busy: "busy" }, prefix: :availability
  enum :recurrence_interval, { no_recurrence: "", daily: "daily", weekly: "weekly", biweekly: "biweekly", monthly: "monthly" },
       prefix: :recurs

  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2_000 }
  validates :place, length: { maximum: 60 }
  validate :assignee_must_be_household_member
  validate :ends_after_start
  validates :recurrence_interval, inclusion: { in: recurrence_intervals.keys }

  # Live updates: every change re-renders the affected person cards on the
  # household's dashboards and wall, and pings the assignee's browser when
  # someone else touched their task.
  after_commit :broadcast_member_cards
  after_commit :notify_assignee, on: [:create, :update]

  # The planned copy a recurring task spawns; its assignee already heard
  # about the task being finished, so it doesn't notify again.
  attr_accessor :recurrence_copy

  # The schedule form's fields: a day, and optionally a from/until time on
  # it. Without a time it's a to-do (for that day, if one was given). Set
  # `schedule_fields` to apply them; other callers set the columns directly.
  attr_accessor :on_date, :from_time, :until_time, :schedule_fields
  before_validation :apply_schedule_fields, if: :schedule_fields

  normalizes :place, with: ->(place) { place.squish.presence }

  STATUS_VERBS = { "in_progress" => "started", "planned" => "paused", "completed" => "finished", "undone" => "skipped" }.freeze

  scope :for_household, ->(household) { where(household_id: household.id) }
  scope :open, -> { where(status: [:planned, :in_progress]) }
  scope :timed, -> { where.not(starts_at: nil) }
  scope :untimed, -> { where(starts_at: nil) }

  def timed?
    starts_at.present?
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
      task.update!(status: :completed)
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

    update!(status: :in_progress, started_at: Time.current)
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

    update!(status: :completed)
    schedule_next_occurrence
    true
  end

  def cancel!
    return false unless open?

    update!(status: :undone)
    schedule_next_occurrence
    true
  end

  # A cancelled recurring task already spawned its next copy on cancel, so
  # restarting it would schedule a duplicate; only one-offs come back.
  def restartable?
    undone? && !recurs?
  end

  private

  def assignee_must_be_household_member
    return if assigned_to_id.blank? || household.blank?

    unless assigned_to && household.users.exists?(assigned_to_id)
      errors.add(:assigned_to_id, "must be a member of the task's household")
    end
  end

  # On finishing/skipping a recurring item, create its next planned copy,
  # then clear next_occurrence on this finished instance. Events move their
  # time along; to-dos come back on the next day/week/month (due_on).
  # Returns the copy.
  def schedule_next_occurrence
    return unless recurs?

    attributes = { recurrence_copy: true, household: household, title: title, description: description,
                   assigned_to: assigned_to, created_by: created_by, recurrence_interval: recurrence_interval,
                   availability: availability, place: place }
    if timed?
      new_starts_at = next_start_from(starts_at) or return
      attributes.merge!(starts_at: new_starts_at, ends_at: ends_at&.then { |e| e + (new_starts_at - starts_at) })
    else
      base = [due_on, Date.current].compact.max
      attributes[:due_on] = next_start_from(base.in_time_zone).to_date
    end

    copy = Task.create!(attributes)
    update_column(:next_occurrence, nil)
    copy
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

    user_ids = [assigned_to_id]
    user_ids << assigned_to_id_before_last_save if saved_change_to_assigned_to_id?
    household&.broadcast_member_cards(user_ids.compact.uniq)
  rescue StandardError => error
    Rails.logger.warn("Live update failed for task #{id}: #{error.class}: #{error.message}")
  end

  def notify_assignee
    actor = Current.user
    return if recurrence_copy || actor.nil? || assigned_to.nil? || assigned_to == actor

    message =
      if previously_new_record? || saved_change_to_assigned_to_id?
        "#{actor.display_name} assigned you: #{title}"
      elsif saved_change_to_status?
        "#{actor.display_name} #{STATUS_VERBS.fetch(status, 'updated')} #{title}"
      end
    return unless message

    Turbo::StreamsChannel.broadcast_append_to(
      assigned_to, :notifications,
      target: "notifications", partial: "shared/notification",
      locals: { title: household.name, body: message, tag: "task-#{id}" }
    )
  rescue StandardError => error
    Rails.logger.warn("Notification failed for task #{id}: #{error.class}: #{error.message}")
  end
end