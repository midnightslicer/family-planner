# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_24_120100) do
  create_table "household_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["household_id"], name: "index_household_memberships_on_household_id"
    t.index ["user_id", "household_id"], name: "index_household_memberships_on_user_id_and_household_id", unique: true
    t.index ["user_id"], name: "index_household_memberships_on_user_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dashboard_token", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["dashboard_token"], name: "index_households_on_dashboard_token", unique: true
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "expires_at", null: false
    t.integer "household_id", null: false
    t.integer "invited_by_id"
    t.string "note"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["household_id"], name: "index_invitations_on_household_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "passkeys", force: :cascade do |t|
    t.integer "algorithm", null: false
    t.boolean "backed_up", default: false, null: false
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.binary "public_key", null: false
    t.integer "sign_count", default: 0, null: false
    t.string "transports"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "assigned_to_id"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.text "description"
    t.datetime "ends_at"
    t.integer "household_id", null: false
    t.datetime "next_occurrence"
    t.string "recurrence_interval", default: "", null: false
    t.datetime "starts_at"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_to_id"], name: "index_tasks_on_assigned_to_id"
    t.index ["created_by_id"], name: "index_tasks_on_created_by_id"
    t.index ["household_id", "assigned_to_id", "status", "starts_at"], name: "index_tasks_on_household_assignee_status"
    t.index ["household_id", "status", "starts_at"], name: "index_tasks_on_household_id_and_status_and_starts_at"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "color", default: "#6366f1", null: false
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "handle"
    t.datetime "onboarding_dismissed_at"
    t.datetime "otp_enabled_at"
    t.integer "otp_last_used_step"
    t.text "otp_recovery_codes"
    t.text "otp_secret"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.string "webauthn_id"
    t.index ["admin"], name: "index_users_on_admin"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["handle"], name: "index_users_on_handle", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  add_foreign_key "household_memberships", "households"
  add_foreign_key "household_memberships", "users"
  add_foreign_key "invitations", "households"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "passkeys", "users"
  add_foreign_key "tasks", "households"
  add_foreign_key "tasks", "users", column: "assigned_to_id"
  add_foreign_key "tasks", "users", column: "created_by_id"
end
