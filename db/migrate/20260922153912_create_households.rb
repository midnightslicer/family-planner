class CreateHouseholds < ActiveRecord::Migration[8.1]
  def change
    create_table :households do |t|
      t.timestamps
    end
  end
end
