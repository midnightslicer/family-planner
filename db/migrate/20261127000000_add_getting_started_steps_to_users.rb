class AddGettingStartedStepsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_setup_skipped_at, :datetime
    add_column :users, :wall_link_opened_at, :datetime
  end
end
