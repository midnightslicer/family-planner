class HouseholdMembership < ApplicationRecord
  belongs_to :user
  belongs_to :household
  # The house they live in, one of the household's locations.
  belongs_to :home, class_name: "Location", optional: true

  validates :user_id, uniqueness: { scope: :household_id }
  validate :home_in_household

  after_save :record_residence, if: :saved_change_to_home_id?

  private

  # Moving house ends the old residence and starts the new one.
  def record_residence
    now = Time.current
    Residence.current.where(user_id: user_id, household_id: household_id).update_all(ended_at: now, updated_at: now)
    Residence.create!(user_id: user_id, household_id: household_id, location_id: home_id, started_at: now) if home_id
  end

  def home_in_household
    errors.add(:home, "must be one of this household's locations") if home && home.household_id != household_id
  end
end
