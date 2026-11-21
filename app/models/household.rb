class Household < ApplicationRecord
  has_many :household_memberships, dependent: :destroy
  has_many :users, through: :household_memberships
  has_many :tasks, dependent: :destroy
  has_many :invitations, dependent: :destroy
  # Reports and feedings go first: they point at pets and locations.
  has_many :location_reports, dependent: :delete_all
  has_many :feedings, dependent: :delete_all
  has_many :pets, dependent: :destroy
  has_many :locations, dependent: :destroy

  validates :name, presence: true, length: { maximum: 80 }

  before_validation :generate_dashboard_token, on: :create

  # Members sorted by display name, as shown on dashboards.
  def members_by_name
    users.order(:display_name)
  end

  # For every member, what they're doing now, their next event within the
  # week, and where they last said they were, in two queries instead of a
  # few per card. "Now" is an event whose time has come, else a to-do they
  # started. Returns { user_id => { current:, next:, location: } }.
  def member_statuses(now = Time.current)
    statuses = Hash.new { |hash, key| hash[key] = {} }
    open_tasks = tasks.open.where.not(assigned_to_id: nil)
                      .where("status = :doing OR (starts_at < :horizon AND COALESCE(ends_at, starts_at) >= :earliest)",
                             doing: Task.statuses[:in_progress], horizon: now + 7.days, earliest: now - Task::DEFAULT_LENGTH)
                      .order(:starts_at, :id).to_a
    open_tasks.group_by(&:assigned_to_id).each do |user_id, items|
      statuses[user_id][:current] = items.find { |task| task.happening_at?(now) } || items.find(&:in_progress?)
      statuses[user_id][:next] = items.find { |task| task.timed? && task.planned? && task.starts_at > now }
    end
    LocationReport.latest_for(self, "User", users.select(:id)).each do |user_id, report|
      statuses[user_id][:location] = report
    end
    statuses
  end

  # Recurring events that ended unmarked move on to their next time. Run
  # before showing schedules (and by ScheduleTickJob in production).
  def roll_recurring_events!(now = Time.current)
    tasks.planned.timed.where.not(recurrence_interval: "")
         .where("COALESCE(ends_at, starts_at) <= ?", now).find_each { |task| task.roll_forward!(now) }
  end

  # Asks every open page subscribed to `turbo_stream_from household, :members`
  # (dashboard, wall, pets, locations, people) to re-fetch itself; they morph
  # in place. Debounced, so a batch of feedings is one refresh.
  def broadcast_refresh
    Turbo::StreamsChannel.broadcast_refresh_later_to(self, :members)
  rescue StandardError => error
    Rails.logger.warn("Live refresh failed for household #{id}: #{error.class}: #{error.message}")
  end

  # Re-renders the given members' cards on every open dashboard and wall for
  # this household (they subscribe with `turbo_stream_from household, :members`).
  def broadcast_member_cards(user_ids)
    return if user_ids.empty?

    statuses = member_statuses
    users.where(id: user_ids).find_each do |user|
      Turbo::StreamsChannel.broadcast_replace_to(
        self, :members,
        target: ActionView::RecordIdentifier.dom_id(user, :person_card),
        partial: "shared/person_card",
        locals: { user: user, household: self, status: statuses[user.id] }
      )
    end
  end

  # Invalidates the old public wall link (e.g. if it was shared too widely).
  def regenerate_dashboard_token!
    update!(dashboard_token: SecureRandom.hex(16))
  end

  private

  def generate_dashboard_token
    self.dashboard_token ||= SecureRandom.hex(16)
  end
end
