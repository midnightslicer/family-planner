# One stretch of a pet being here: from arrival until it left (nil while
# it's still here). Opened when a pet is added or comes back, closed when
# it goes away or is removed (Pet#arrive!, #leave!).
class PetVisit < ApplicationRecord
  belongs_to :pet
  belongs_to :household

  scope :open, -> { where(left_at: nil) }

  # How long it lasted (so far, if still open).
  def duration(now = Time.current)
    (left_at || now) - arrived_at
  end
end
