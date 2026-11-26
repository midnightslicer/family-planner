# How each person hears about each kind of update: push, email, both or
# neither. A missing row means NotificationPreference's defaults, so new
# categories and existing people need no backfill.
class CreateNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :category, null: false
      t.boolean :push, null: false
      t.boolean :email, null: false
      t.timestamps
    end
    add_index :notification_preferences, [ :user_id, :category ], unique: true

    change_table :users, bulk: true do |t|
      t.integer :reminder_lead_minutes, null: false, default: 15
      t.integer :digest_hour, null: false, default: 7
      # Minutes after midnight on the household's clock; nil = no quiet hours.
      t.integer :quiet_hours_start
      t.integer :quiet_hours_end
      t.datetime :notifications_paused_until
    end
  end
end
