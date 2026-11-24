# "I'm free / text only / do not disturb", set by hand from your day. One
# row per tap, kept as history: the newest unexpired one overrides what
# work hours and events say until `expires_at` (12 hours on, so a
# forgotten "do not disturb" doesn't stick).
class CreateStatusUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :status_updates do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :availability, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :status_updates, [:user_id, :id]
  end
end
