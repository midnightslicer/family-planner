class AddFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :handle, :string
    add_column :users, :display_name, :string
    add_column :users, :color, :string
    add_column :users, :admin, :boolean
  end
end
