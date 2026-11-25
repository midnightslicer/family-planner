class AddSessionTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    # Part of every session's salt (User#authenticatable_salt): changing it
    # signs the person out everywhere.
    add_column :users, :session_token, :string
  end
end
