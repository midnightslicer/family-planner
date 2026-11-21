# A stretch of someone living in a house: kept when they move, so history
# can say who lived where when (HouseholdMembership#home is only "now").
class Residence < ApplicationRecord
  belongs_to :user
  belongs_to :household
  belongs_to :location

  scope :current, -> { where(ended_at: nil) }
end
