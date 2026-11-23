# One row per browser that agreed to receive pushes (a phone, a laptop).
# The endpoint is the push service URL the browser gave us; p256dh and auth
# are its encryption keys (RFC 8291), encrypted at rest.
class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.text :p256dh, null: false
      t.text :auth, null: false
      t.string :user_agent
      t.datetime :last_used_at
      t.string :last_error
      t.datetime :failed_at
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
  end
end
