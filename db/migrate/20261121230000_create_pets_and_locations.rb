# Pets, the places they (and people) can be, where everyone was last seen,
# and when the pets were fed.
class CreatePetsAndLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :locations do |t|
      t.references :household, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :kind, null: false, default: "other"
      t.timestamps
    end

    create_table :pets do |t|
      t.references :household, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :home, foreign_key: { to_table: :locations }
      t.string :name, null: false
      t.string :species
      t.date :birthday
      t.integer :meals_per_day, null: false, default: 2
      t.text :feeding_notes
      t.timestamps
    end

    # History of "X is at Y". The newest row per subject is where they are
    # now. location_id is nulled if the place is deleted ("somewhere else").
    create_table :location_reports do |t|
      t.references :household, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false, index: false
      t.references :location, foreign_key: true
      t.references :reported_by, foreign_key: { to_table: :users }
      t.string :comment
      t.datetime :created_at, null: false
    end
    add_index :location_reports, [ :subject_type, :subject_id, :id ]
    add_index :location_reports, [ :household_id, :subject_type, :id ]

    create_table :feedings do |t|
      t.references :household, null: false, foreign_key: true
      t.references :pet, null: false, foreign_key: true, index: false
      t.references :fed_by, foreign_key: { to_table: :users }
      t.string :comment
      t.datetime :created_at, null: false
    end
    add_index :feedings, [ :pet_id, :created_at ]

    add_column :users, :birthday, :date
  end
end
