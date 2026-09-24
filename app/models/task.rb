class Task < ApplicationRecord
  belongs_to :household
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :status, { planned: 0, in_progress: 1, undone: 2, completed: 3 }
  enum :recurrence_interval, { no_recurrence: "", daily: "daily", weekly: "weekly", biweekly: "biweekly", monthly: "monthly" },
       prefix: :recurs

  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2_000 }
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

  STATUS_VERBS = { "in_progress" => "started", "planned" => "paused", "completed" => "finished", "undone" => "skipped" }.freeze

  scope :for_household, ->(household) { where(household_id: household.id) }

  # Transitions: planned→in_progress ("Start"), undone→in_progress (restart a
  # cancelled one-off), in_progress→planned ("Pause"), in_progress→completed,
  # in_progress→undone ("Never mind"). Any other transition is ignored (false).
  def start!
    return false unless planned? || restartable?

    update!(status: :in_progress, starts_at: starts_at || Time.current)
    true
  end

  # Keeps starts_at, so Start picks the task back up where it was.
  def pause!
    return false unless in_progress?

    update!(status: :planned)
    true
  end

  def complete!
    return false unless in_progress?

    update!(status: :completed)
    schedule_next_occurrence
    true
  end

  def cancel!
    return false unless in_progress?

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

  # On finishing/cancelling a recurring task, create a new planned copy with
  # the next start time computed from starts_at, then clear next_occurrence
  # on this finished instance.
  def schedule_next_occurrence
    return unless recurs?

    new_starts_at = next_start_from(starts_at)
    return if new_starts_at.nil?

    Task.create!(
      recurrence_copy: true,
      household: household,
      title: title,
      description: description,
      assigned_to: assigned_to,
      created_by: created_by,
      starts_at: new_starts_at,
      ends_at: ends_at&.then { |e| e + (new_starts_at - (starts_at || new_starts_at)) },
      recurrence_interval: recurrence_interval
    )
    update_column(:next_occurrence, nil)
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