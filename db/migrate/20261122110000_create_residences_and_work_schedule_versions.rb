# History for things that otherwise only hold their current value: which
# house someone lived in when, and each version of their work schedule.
class CreateResidencesAndWorkScheduleVersions < ActiveRecord::Migration[8.1]
  def up
    create_table :residences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :household, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.timestamps
    end

    create_table :work_schedule_versions do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :effective_at, null: false
      t.string :availability, null: false
      t.json :shifts, null: false # [{ weekday:, from_time:, until_time:, place: }]
      t.timestamps
    end

    execute <<~SQL
      INSERT INTO residences (user_id, household_id, location_id, started_at, created_at, updated_at)
      SELECT user_id, household_id, home_id, updated_at, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM household_memberships WHERE home_id IS NOT NULL
    SQL
  end

  def down
    drop_table :work_schedule_versions
    drop_table :residences
  end
end
