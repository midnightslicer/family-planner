class AddLastSeenVersionToUsers < ActiveRecord::Migration[8.1]
  # Blank for everyone already here, so they see what's new in this update once.
  def change
    add_column :users, :last_seen_version, :string
  end
end
