# Pets that never move (horses in their pasture) can leave the "Where" page.
class AddOnWherePageToPets < ActiveRecord::Migration[8.1]
  def change
    add_column :pets, :on_where_page, :boolean, default: true, null: false
  end
end
