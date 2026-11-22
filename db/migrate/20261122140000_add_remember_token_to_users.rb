# Devise's "remember me" cookie is keyed on the password hash unless there's
# a remember_token column, so passkey-only accounts (no password) crashed on
# passkey sign-in. A token of its own works whether or not there's a password.
class AddRememberTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :remember_token, :string
  end
end
