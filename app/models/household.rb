class Household < ApplicationRecord
  has_many :household_memberships, dependent: :destroy
  has_many :users, through: :household_memberships
  has_many :tasks, dependent: :destroy
  has_many :invitations, dependent: :destroy

  validates :name, presence: true

  before_validation :generate_dashboard_token, on: :create

  # Members sorted by display name, as shown on dashboards.
  def members_by_name
    users.order(:display_name)
  end

  private

  def generate_dashboard_token
    self.dashboard_token ||= SecureRandom.hex(16)
  end
end