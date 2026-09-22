class CreateHouseholdMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :household_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :household, null: false, foreign_key: true
      t.timestamps
    end
    add_index :household_memberships, [:user_id, :household_id], unique: true
  end
end