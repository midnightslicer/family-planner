class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.string :email, null: false
      t.references :household, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.references :invited_by, foreign_key: { to_table: :users }
      t.string :note
    end
    add_index :invitations, :email
    add_index :invitations, :token, unique: true
  end
end