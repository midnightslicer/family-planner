class TuneTaskIndexesAndOptionalInviteEmail < ActiveRecord::Migration[8.1]
  def change
    # An invite link can be sent by text; the person enters their own email.
    change_column_null :invitations, :email, true

    # Person cards look up a member's current/next task; the task list reads
    # a household's tasks by status. Both lead with household_id, which makes
    # the single-column index redundant.
    remove_index :tasks, :household_id
    add_index :tasks, [:household_id, :status, :starts_at]
    add_index :tasks, [:household_id, :assigned_to_id, :status, :starts_at], name: "index_tasks_on_household_assignee_status"
  end
end
