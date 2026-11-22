class AddWorkScheduleSkippedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :work_schedule_skipped_at, :datetime
  end
end
