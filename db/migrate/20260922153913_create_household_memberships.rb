class CreateHouseholdMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :household_memberships do |t|
      t.timestamps
    end
  end
end
