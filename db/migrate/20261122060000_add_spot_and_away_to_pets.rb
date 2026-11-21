# Inside or outside, when a pet is reported at a house; and pets that come
# and go (dog-sitting), marked away rather than deleted.
class AddSpotAndAwayToPets < ActiveRecord::Migration[8.1]
  def change
    add_column :location_reports, :spot, :string # "inside" / "outside", houses only
    add_column :pets, :away_since, :datetime
  end
end
