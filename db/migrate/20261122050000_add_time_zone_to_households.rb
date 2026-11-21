# The household's own clock: work hours, "today", and every time shown are
# in it, whoever is looking and wherever their phone is. Blank until an
# admin sets it (until then each browser's zone is used, as before).
class AddTimeZoneToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :time_zone, :string
  end
end
