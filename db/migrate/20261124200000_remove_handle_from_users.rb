# Handles (@name on the board) are gone: people go by their name.
class RemoveHandleFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :handle, unique: true
    remove_column :users, :handle, :string
  end
end
