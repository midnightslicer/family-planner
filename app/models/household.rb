class Household < ApplicationRecord
  has_many :household_memberships, dependent: :destroy
  has_many :users, through: :household_memberships
  has_many :tasks, dependent: :destroy
  has_many :invitations, dependent: :destroy

  validates :name, presence: true, length: { maximum: 80 }

  before_validation :generate_dashboard_token, on: :create

  # Members sorted by display name, as shown on dashboards.
  def members_by_name
    users.order(:display_name)
  end

  # For every member, their current (in-progress) and next (planned) task, in
  # one query instead of two per person card.
  # Returns { user_id => { current: Task, next: Task } }.
  def member_statuses
    tasks.where(status: [:in_progress, :planned]).where.not(assigned_to_id: nil)
         .order(:starts_at, :id)
         .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |task, statuses|
      slot = task.in_progress? ? :current : :next
      statuses[task.assigned_to_id][slot] ||= task
    end
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
