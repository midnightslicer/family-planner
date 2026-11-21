# Someone following a pet: they get a notification whenever somebody else
# reports where it is or feeds it (see PetCheckIn#notify_subscribers).
class PetSubscription < ApplicationRecord
  belongs_to :pet
  belongs_to :user

  validates :user_id, uniqueness: { scope: :pet_id }
  validate :user_in_pets_household

  private

  def user_in_pets_household
    errors.add(:user, "must be in the pet's household") if pet && user && !user.member_of?(pet.household)
  end
end
