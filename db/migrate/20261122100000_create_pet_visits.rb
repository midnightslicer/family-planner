# Each stretch a pet is here: arrived, and left (nil while still here).
# With `visitor` (dogs we sit), "Pepper was here 3 days last year" is a sum.
class CreatePetVisits < ActiveRecord::Migration[8.1]
  def up
    add_column :pets, :visitor, :boolean, null: false, default: false

    create_table :pet_visits do |t|
      t.references :pet, null: false, foreign_key: true, index: false
      t.references :household, null: false, foreign_key: true
      t.datetime :arrived_at, null: false
      t.datetime :left_at
      t.timestamps
    end
    add_index :pet_visits, [:pet_id, :arrived_at]

    # Everyone so far: here since they were added, until they went away or
    # were removed.
    execute <<~SQL
      INSERT INTO pet_visits (pet_id, household_id, arrived_at, left_at, created_at, updated_at)
      SELECT id, household_id, created_at, COALESCE(away_since, archived_at), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM pets
    SQL
  end

  def down
    drop_table :pet_visits
    remove_column :pets, :visitor
  end
end
