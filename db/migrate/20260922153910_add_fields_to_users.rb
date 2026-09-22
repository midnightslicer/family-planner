class AddFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :handle, :string
    add_column :users, :display_name, :string
    add_column :users, :color, :string, default: "#6366f1", null: false
    add_column :users, :admin, :boolean, default: false, null: false
    add_index :users, :handle, unique: true
    add_index :users, :admin
  end
end