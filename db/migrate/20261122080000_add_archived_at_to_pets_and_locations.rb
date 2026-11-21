# Removing a pet or a location archives it, so the reports, feedings and
# events that mention it keep their history (and the place keeps its name).
class AddArchivedAtToPetsAndLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :pets, :archived_at, :datetime
    add_column :locations, :archived_at, :datetime
  end
end
