# Optional weekly work hours per person (a row per working weekday, each
# with its own place, for hybrid weeks), how reachable they are at work,
# and days off.
class CreateWorkSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :work_shifts do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.integer :weekday, null: false # 0 = Sunday, as Date#wday
      t.string :from_time, null: false # "09:00"
      t.string :until_time, null: false
      t.string :place
      t.timestamps
    end
    add_index :work_shifts, [ :user_id, :weekday ], unique: true

    create_table :days_off do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.string :note
      t.timestamps
    end
    add_index :days_off, [ :user_id, :starts_on, :ends_on ]

    add_column :users, :work_availability, :string, null: false, default: "text"
  end
end
