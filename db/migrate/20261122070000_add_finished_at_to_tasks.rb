# When an item was finished or skipped, kept apart from updated_at (which a
# later edit moves) so history and charts can rely on it. Past items get
# their last change as a best guess.
class AddFinishedAtToTasks < ActiveRecord::Migration[8.1]
  def up
    add_column :tasks, :finished_at, :datetime
    execute "UPDATE tasks SET finished_at = updated_at WHERE status IN (2, 3)"
    add_index :tasks, [ :household_id, :finished_at ]
  end

  def down
    remove_column :tasks, :finished_at
  end
end
