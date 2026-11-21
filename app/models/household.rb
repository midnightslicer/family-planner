class Household < ApplicationRecord
  has_many :household_memberships, dependent: :destroy
  has_many :users, through: :household_memberships
  has_many :tasks, dependent: :destroy
  has_many :invitations, dependent: :destroy
  # Reports and feedings go first: they point at pets and locations.
  has_many :location_reports, dependent: :delete_all
  has_many :feedings, dependent: :delete_all
  # `pets` and `locations` are the ones in use; removing one archives it, so
  # history that mentions it keeps it. `all_*` include the archived ones.
  has_many :residences, dependent: :delete_all
  has_many :all_pets, class_name: "Pet", dependent: :destroy
  has_many :all_locations, class_name: "Location", dependent: :destroy
  has_many :pets, -> { where(archived_at: nil) }, inverse_of: :household
  has_many :locations, -> { where(archived_at: nil) }, inverse_of: :household

  validates :name, presence: true, length: { maximum: 80 }
  validate :time_zone_is_known

  normalizes :time_zone, with: ->(zone) { zone.strip.presence }

  before_validation :generate_dashboard_token, on: :create

  # Members sorted by display name, as shown on dashboards.
  def members_by_name
    users.order(:display_name)
  end

  # People and pets grouped by the house they live in, houses in display
  # order, then anyone without one: [[house or nil, members, pets], ...].
  # Empty groups are left out.
  def by_house(members = members_by_name.to_a, pets = self.pets.here.by_name.to_a)
    homes = household_memberships.pluck(:user_id, :home_id).to_h
    houses = locations.in_display_order.to_a
    groups = houses.map { |house| [house, members.select { |m| homes[m.id] == house.id }, pets.select { |p| p.home_id == house.id }] }
    housed = houses.map(&:id)
    groups << [nil, members.reject { |m| housed.include?(homes[m.id]) }, pets.reject { |p| housed.include?(p.home_id) }]
    groups.reject { |_, people, animals| people.empty? && animals.empty? }
  end

  # For every member, what they're doing now, what's next, whether they're
  # off today and where they are, in a fixed handful of queries rather than
  # a few per card. "Now" is an event whose time has come, else a to-do
  # they started, else their work hours (WorkBlock); `at` is the location
  # that puts them at, which outranks their last "I'm at"; `off` is today's
  # DayOff. Returns { user_id => { current:, next:, at:, off:, location: } }.
  def member_statuses(now = Time.current)
    statuses = Hash.new { |hash, key| hash[key] = {} }
    # One row per (item, person who accepted it): shared items count for
    # everyone on them.
    open_tasks = tasks.open.joins(:assignments).merge(TaskAssignment.accepted).includes(:location)
                      .select("tasks.*, task_assignments.user_id AS person_id")
                      .where("tasks.status = :doing OR (tasks.starts_at < :horizon AND COALESCE(tasks.ends_at, tasks.starts_at) >= :earliest)",
                             doing: Task.statuses[:in_progress], horizon: now + 7.days, earliest: now - Task::DEFAULT_LENGTH)
                      .order(:starts_at, :id).to_a
    by_user = open_tasks.group_by(&:person_id)
    places = locations.to_a
    users.includes(:work_shifts, :days_off).each do |user|
      items = by_user.fetch(user.id, [])
      status = statuses[user.id]
      status[:current] = items.find { |task| task.happening_at?(now) } || items.find(&:in_progress?) ||
                         WorkBlock.current(user, now, locations: places)
      status[:at] = status[:current]&.whereabouts(now)
      upcoming_work = WorkBlock.on(user, now.to_date, locations: places)
      upcoming_work = nil unless upcoming_work&.starts_at&.>(now)
      status[:next] = [items.find { |task| task.timed? && task.planned? && task.starts_at > now }, upcoming_work]
                      .compact.min_by(&:starts_at)
      status[:off] = user.day_off_on(now.to_date)
      statuses.delete(user.id) if status.compact.empty?
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

  # The household's clock (an ActiveSupport::TimeZone), or nil if no admin
  # has set one yet.
  def zone
    ActiveSupport::TimeZone[time_zone] if time_zone
  end

  # Invalidates the old public wall link (e.g. if it was shared too widely).
  def regenerate_dashboard_token!
    update!(dashboard_token: SecureRandom.hex(16))
  end

  private

  def time_zone_is_known
    errors.add(:time_zone, "isn't a time zone we know") if time_zone && zone.nil?
  end

  def generate_dashboard_token
    self.dashboard_token ||= SecureRandom.hex(16)
  end
end
