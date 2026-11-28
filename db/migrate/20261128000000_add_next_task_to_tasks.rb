# The planned copy a recurring item spawned when it was finished or skipped,
# so bringing the finished one back can take the copy away again.
class AddNextTaskToTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :tasks, :next_task, foreign_key: { to_table: :tasks, on_delete: :nullify }
  end
end
