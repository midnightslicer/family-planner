# Pets that never move (horses in their pasture) needn't take space on the
# wall: each pet can be left off it. They stay everywhere else in the app.
class AddOnWallToPets < ActiveRecord::Migration[8.1]
  def change
    add_column :pets, :on_wall, :boolean, default: true, null: false
  end
end
