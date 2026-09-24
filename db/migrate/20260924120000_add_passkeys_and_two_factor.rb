class AddPasskeysAndTwoFactor < ActiveRecord::Migration[8.1]
  def change
    # Random WebAuthn user handle, so passkeys never carry an email or id.
    add_column :users, :webauthn_id, :string
    add_index :users, :webauthn_id, unique: true

    # TOTP: secret is encrypted at rest; the last accepted time step blocks
    # code replay; recovery codes are stored as HMAC digests.
    add_column :users, :otp_secret, :text
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_used_step, :integer
    add_column :users, :otp_recovery_codes, :text

    add_column :users, :onboarding_dismissed_at, :datetime

    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.binary :public_key, null: false
      t.integer :algorithm, null: false
      t.integer :sign_count, null: false, default: 0
      t.string :name, null: false
      t.string :transports
      t.boolean :backed_up, null: false, default: false
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :passkeys, :external_id, unique: true
  end
end
