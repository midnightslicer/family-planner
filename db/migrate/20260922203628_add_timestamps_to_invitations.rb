class AddTimestampsToInvitations < ActiveRecord::Migration[8.1]
  # Every other table was created with t.timestamps; invitations was not, so
  # Admin::InvitationsController#index (order(created_at: :desc)) raised.
  # Existing rows get the migration time rather than NULL.
  def up
    add_timestamps :invitations, default: -> { "CURRENT_TIMESTAMP" }, null: false
    change_column_default :invitations, :created_at, nil
    change_column_default :invitations, :updated_at, nil
  end

  def down
    remove_columns :invitations, :created_at, :updated_at
  end
end
