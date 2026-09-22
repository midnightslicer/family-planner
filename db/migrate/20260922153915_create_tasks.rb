class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :household, null: false, foreign_key: true, index: true
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.references :assigned_to, foreign_key: { to_table: :users }, index: true
      t.references :created_by, foreign_key: { to_table: :users }, index: true
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :recurrence_interval, null: false, default: ""
      t.datetime :next_occurrence
      t.timestamps
    end
  end
end