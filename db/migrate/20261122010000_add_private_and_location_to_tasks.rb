# Private items (others see only "Busy"), and events linked to a household
# location, which places the person there while the event is on.
class AddPrivateAndLocationToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :private, :boolean, null: false, default: false
    add_reference :tasks, :location, foreign_key: true
  end
end
