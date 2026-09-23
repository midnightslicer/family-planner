class Task < ApplicationRecord
  belongs_to :household
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :status, { planned: 0, in_progress: 1, undone: 2, completed: 3 }
  enum :recurrence_interval, { no_recurrence: "", daily: "daily", weekly: "weekly", biweekly: "biweekly", monthly: "monthly" },
       prefix: :recurs

  validates :title, presence: true
  validate :assignee_must_be_household_member
  validates :recurrence_interval, inclusion: { in: recurrence_intervals.keys }
  after_commit :broadcast_change, on: [:create, :update]
  after_destroy :broadcast_destroy

  scope :for_household, ->(household) { where(household_id: household.id) }

  # Transitions: planned→in_progress ("Start"), in_progress→planned ("Pause"),
  # in_progress→completed, in_progress→undone ("Cancel"). Any other
  # transition is ignored (false).
  def start!
    return false unless planned?

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

  def broadcast_change
    TaskBroadcaster.broadcast(household_id, {
      type: "task_update",
      task_id: id,
      household_id: household_id,
      assigned_to_id: assigned_to_id,
      event: action_name_for_broadcast
    })
  rescue StandardError
    Rails.logger.info("TaskBroadcaster unavailable: #{$ERROR_INFO.message}")
  end

  def broadcast_destroy
    TaskBroadcaster.broadcast(household_id, {
      type: "task_destroy",
      task_id: id,
      household_id: household_id,
      assigned_to_id: assigned_to_id,
      event: "destroyed"
    })
  rescue StandardError
    Rails.logger.info("TaskBroadcaster unavailable: #{$ERROR_INFO.message}")
  end

  def action_name_for_broadcast
    if previously_changed? :status
      "status_change"
    else
      "created"
    end
  end

  def previously_changed?(attr)
    previous_changes.key?(attr.to_s)
  end
end