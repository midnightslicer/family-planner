# Items can be for several people (church for two), each of whom accepts it
# (automatically, unless it clashes with their schedule) or declines it.
# Replaces tasks.assigned_to_id. `follow_up` keeps the item on its
# creator's list and tells them how it went.
class CreateTaskAssignments < ActiveRecord::Migration[8.1]
  def up
    create_table :task_assignments do |t|
      t.references :task, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false
      t.string :status, null: false, default: "accepted" # accepted, pending, declined
      t.string :conflict_note
      t.datetime :responded_at
      t.timestamps
    end
    add_index :task_assignments, [ :task_id, :user_id ], unique: true
    add_index :task_assignments, [ :user_id, :status ]

    execute <<~SQL
      INSERT INTO task_assignments (task_id, user_id, status, created_at, updated_at)
      SELECT id, assigned_to_id, 'accepted', created_at, updated_at FROM tasks WHERE assigned_to_id IS NOT NULL
    SQL

    add_column :tasks, :follow_up, :boolean, null: false, default: false
    remove_index :tasks, name: "index_tasks_on_household_assignee_status"
    remove_index :tasks, [ :household_id, :assigned_to_id, :due_on ]
    remove_reference :tasks, :assigned_to, foreign_key: { to_table: :users }, index: true
    add_index :tasks, [ :household_id, :status, :due_on ]
  end

  def down
    add_reference :tasks, :assigned_to, foreign_key: { to_table: :users }
    execute <<~SQL
      UPDATE tasks SET assigned_to_id = (SELECT user_id FROM task_assignments a
        WHERE a.task_id = tasks.id AND a.status = 'accepted' ORDER BY a.id LIMIT 1)
    SQL
    remove_index :tasks, [ :household_id, :status, :due_on ]
    add_index :tasks, [ :household_id, :assigned_to_id, :due_on ]
    add_index :tasks, [ :household_id, :assigned_to_id, :status, :starts_at ], name: "index_tasks_on_household_assignee_status"
    remove_column :tasks, :follow_up
    drop_table :task_assignments
  end
end
