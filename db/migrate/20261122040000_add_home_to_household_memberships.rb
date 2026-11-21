# Which house each person lives in (one of the household's locations), so
# the board can group people and pets by house.
class AddHomeToHouseholdMemberships < ActiveRecord::Migration[8.1]
  def change
    add_reference :household_memberships, :home, foreign_key: { to_table: :locations }
  end
end
