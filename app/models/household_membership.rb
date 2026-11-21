class HouseholdMembership < ApplicationRecord
  belongs_to :user
  belongs_to :household
  # The house they live in, one of the household's locations.
  belongs_to :home, class_name: "Location", optional: true

  validates :user_id, uniqueness: { scope: :household_id }
  validate :home_in_household

  private

  def home_in_household
    errors.add(:home, "must be one of this household's locations") if home && home.household_id != household_id
  end
end
