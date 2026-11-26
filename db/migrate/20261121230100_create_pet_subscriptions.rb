# People who want to hear when a pet is moved or fed.
class CreatePetSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :pet_subscriptions do |t|
      t.references :pet, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.datetime :created_at, null: false
    end
    add_index :pet_subscriptions, [ :pet_id, :user_id ], unique: true
  end
end
