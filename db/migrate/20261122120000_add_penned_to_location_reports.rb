class AddPennedToLocationReports < ActiveRecord::Migration[8.1]
  def change
    add_column :location_reports, :penned, :boolean, null: false, default: false
  end
end
