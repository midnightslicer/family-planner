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
  # The wall's address: /h/<slug>. Not a secret (the wall needs sign-in).
  validates :slug, presence: true, length: { maximum: 60 }, uniqueness: true,
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, message: "can only have lowercase letters, numbers and dashes" }
  validate :time_zone_is_known

  normalizes :time_zone, with: ->(zone) { zone.strip.presence }
  normalizes :slug, with: ->(slug) { slug.to_s.parameterize.presence }

  before_validation :generate_slug, on: :create

  # Members sorted by display name, as shown on dashboards.
  def members_by_name
    users.order(:display_name)
  end

  # Members as the boards show them, loaded once per page with everything
  # their cards and statuses read (work hours, days off, photo).
  def board_members
    members_by_name.includes(:work_shifts, :days_off).with_attached_avatar.to_a
  end

  # The household's places in display order, with photos: loaded once per
  # page and handed to whatever needs them.
  def places
    locations.in_display_order.with_attached_photo.to_a
  end

  # People and pets grouped by the house they live in, houses in display
  # order, then anyone without one: [[house or nil, members, pets], ...].
  # Empty groups are left out. `houses` is #places, if the page has them.
  def by_house(members = members_by_name.to_a, pets = self.pets.here.by_name.to_a, houses = locations.in_display_order.to_a)
    homes = household_memberships.pluck(:user_id, :home_id).to_h
    people = members.group_by { |member| homes[member.id] }
    animals = pets.group_by(&:home_id)
    groups = houses.map { |house| [ house, people.fetch(house.id, []), animals.fetch(house.id, []) ] }
    housed = houses.to_set(&:id)
    groups << [ nil, members.reject { |m| housed.include?(homes[m.id]) }, pets.reject { |p| housed.include?(p.home_id) } ]
    groups.reject { |_, who, pets_here| who.empty? && pets_here.empty? }
  end

  # For every member, what they're doing now, what's next, whether they're
  # off today and where they are, in a fixed handful of queries rather than
  # a few per card. "Now" is an event whose time has come, else a to-do
  # they started, else their work hours (WorkBlock); `at` is the location
  # that puts them at, which outranks their last "I'm at"; `off` is today's
  # DayOff. Returns { user_id => { current:, next:, at:, off:, location: } }.
  # Pass `members` (with work_shifts and days_off loaded, as #board_members
  # has them) and `places` when the page already has them.
  def member_statuses(now = Time.current, members: users.includes(:work_shifts, :days_off).to_a, places: locations.to_a)
    statuses = Hash.new { |hash, key| hash[key] = {} }
    ids = members.map(&:id)
    # One row per (item, person who accepted it): shared items count for
    # everyone on them.
    by_user = tasks.open.joins(:assignments).merge(TaskAssignment.accepted).where(task_assignments: { user_id: ids })
                   .preload(:location)
                   .select("tasks.*, task_assignments.user_id AS person_id")
                   .where("tasks.status = :doing OR (tasks.starts_at < :horizon AND COALESCE(tasks.ends_at, tasks.starts_at) >= :earliest)",
                          doing: Task.statuses[:in_progress], horizon: now + 7.days, earliest: now - Task::DEFAULT_LENGTH)
                   .order(:starts_at, :id).group_by(&:person_id)
    today = now.to_date
    members.each do |user|
      items = by_user.fetch(user.id, [])
      status = statuses[user.id]
      status[:current] = items.find { |task| task.happening_at?(now) } || items.find(&:in_progress?) ||
                         WorkBlock.current(user, now, locations: places)
      status[:at] = status[:current]&.whereabouts(now)
      upcoming_work = WorkBlock.on(user, today, locations: places)
      upcoming_work = nil unless upcoming_work&.starts_at&.>(now)
      status[:next] = [ items.find { |task| task.timed? && task.planned? && task.starts_at > now }, upcoming_work ]
                      .compact.min_by(&:starts_at)
      status[:off] = user.day_off_on(today)
      statuses.delete(user.id) if status.compact.empty?
    end
    StatusUpdate.active_for(ids, now).each do |user_id, update|
      statuses[user_id][:set] = update
    end
    LocationReport.latest_for(self, "User", ids).each do |user_id, report|
      status = statuses[user_id]
      status[:location] = report
      status.delete(:at) if status[:at] && report.newer_than?(status[:current])
    end
    statuses
  end

  # Recurring events that ended unmarked move on to their next time. Run
  # before showing schedules (and by ScheduleTickJob in production).
  def roll_recurring_events!(now = Time.current)
    Household.batching_cards { tasks.ended_repeats(now).find_each { |task| task.roll_forward!(now) } }
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
  # Inside Household.batching_cards (every request) they go out once, at the
  # end, however many records changed.
  def broadcast_member_cards(user_ids)
    return if user_ids.empty?

    if (pending = Current.pending_cards)
      pending[id] ||= [ self, Set.new ]
      pending[id].last.merge(user_ids)
    else
      broadcast_cards_now(user_ids)
    end
  end

  # Collects the card re-renders asked for in the block and sends each
  # person's card once when it ends: saving an item, its people and its next
  # repeat is one status lookup and one card each, not one per record. What
  # was committed still goes out if the block raises.
  def self.batching_cards
    return yield if Current.pending_cards

    Current.pending_cards = pending = {}
    yield
  ensure
    if pending # the outermost batch
      Current.pending_cards = nil
      pending.each_value { |household, ids| household.send(:broadcast_cards_now, ids.to_a) }
    end
  end

  # The household's clock (an ActiveSupport::TimeZone), or nil if no admin
  # has set one yet.
  def zone
    ActiveSupport::TimeZone[time_zone] if time_zone
  end

  private

  def broadcast_cards_now(user_ids)
    members = users.includes(:work_shifts, :days_off).with_attached_avatar.to_a
    statuses = member_statuses(members: members)
    members.each do |user|
      next unless user_ids.include?(user.id)

      Turbo::StreamsChannel.broadcast_replace_to(
        self, :members,
        target: ActionView::RecordIdentifier.dom_id(user, :person_card),
        partial: "shared/person_card",
        locals: { user: user, household: self, status: statuses[user.id] }
      )
    end
  rescue StandardError => error
    Rails.logger.warn("Live card update failed for household #{id}: #{error.class}: #{error.message}")
  end

  def time_zone_is_known
    errors.add(:time_zone, "isn't a time zone we know") if time_zone && zone.nil?
  end

  # "The Smiths" -> "the-smiths"; "the-smiths-2" if that's taken.
  def generate_slug
    return if slug.present?

    base = name.to_s.parameterize.first(50).presence || "home"
    candidate = base
    count = 1
    candidate = "#{base}-#{count += 1}" while Household.exists?(slug: candidate)
    self.slug = candidate
  end
end
