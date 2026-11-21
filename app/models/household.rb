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

  # For every member, their current (in-progress) and next (planned) task and
  # where they last said they were, in two queries instead of a few per card.
  # Returns { user_id => { current: Task, next: Task, location: LocationReport } }.
  def member_statuses
    statuses = Hash.new { |hash, key| hash[key] = {} }
    tasks.where(status: [:in_progress, :planned]).where.not(assigned_to_id: nil)
         .order(:starts_at, :id).each do |task|
      slot = task.in_progress? ? :current : :next
      statuses[task.assigned_to_id][slot] ||= task
    end
    LocationReport.latest_for(self, "User", users.select(:id)).each do |user_id, report|
      statuses[user_id][:location] = report
    end
    statuses
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
