# Who finished (or skipped) an item: for shared items, whoever ticked it.
# Past items are credited to their one person, when they had just one.
class AddFinishedByToTasks < ActiveRecord::Migration[8.1]
  def up
    add_reference :tasks, :finished_by, foreign_key: { to_table: :users }
    execute <<~SQL
      UPDATE tasks SET finished_by_id = (
        SELECT MIN(a.user_id) FROM task_assignments a WHERE a.task_id = tasks.id AND a.status = 'accepted'
      )
      WHERE status IN (2, 3)
        AND (SELECT COUNT(*) FROM task_assignments a WHERE a.task_id = tasks.id AND a.status = 'accepted') = 1
    SQL
  end

  def down
    remove_reference :tasks, :finished_by, foreign_key: { to_table: :users }
  end
end
