# Tasks become schedule items: a to-do (no time; optionally for a given day,
# due_on) or an event (starts_at/ends_at, maybe a place), each saying how
# reachable the person is meanwhile. started_at records "I'm doing this now"
# so it no longer overwrites starts_at, which now always means a set time.
class TurnTasksIntoScheduleItems < ActiveRecord::Migration[8.1]
  def up
    add_column :tasks, :availability, :string, null: false, default: "text"
    add_column :tasks, :place, :string
    add_column :tasks, :due_on, :date
    add_column :tasks, :started_at, :datetime
    add_index :tasks, [ :household_id, :assigned_to_id, :due_on ]

    # Start used to stamp starts_at on to-dos; move that stamp to started_at
    # where the task had no end time (so it was never a scheduled event).
    execute <<~SQL
      UPDATE tasks SET started_at = starts_at, starts_at = NULL
      WHERE status = 1 AND ends_at IS NULL AND starts_at IS NOT NULL
    SQL
  end

  def down
    execute "UPDATE tasks SET starts_at = started_at WHERE starts_at IS NULL AND started_at IS NOT NULL"
    remove_index :tasks, [ :household_id, :assigned_to_id, :due_on ]
    remove_column :tasks, :started_at
    remove_column :tasks, :due_on
    remove_column :tasks, :place
    remove_column :tasks, :availability
  end
end
