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

ActiveRecord::Schema[8.1].define(version: 2026_11_23_010000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "days_off", force: :cascade do |t|
    t.integer "user_id", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "starts_on", "ends_on"], name: "index_days_off_on_user_id_and_starts_on_and_ends_on"
  end

  create_table "feedings", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "pet_id", null: false
    t.integer "fed_by_id"
    t.string "comment"
    t.datetime "created_at", null: false
    t.index ["fed_by_id"], name: "index_feedings_on_fed_by_id"
    t.index ["household_id"], name: "index_feedings_on_household_id"
    t.index ["pet_id", "created_at"], name: "index_feedings_on_pet_id_and_created_at"
  end

  create_table "household_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "home_id"
    t.index ["home_id"], name: "index_household_memberships_on_home_id"
    t.index ["household_id"], name: "index_household_memberships_on_household_id"
    t.index ["user_id", "household_id"], name: "index_household_memberships_on_user_id_and_household_id", unique: true
    t.index ["user_id"], name: "index_household_memberships_on_user_id"
  end

  create_table "households", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "time_zone"
    t.string "slug", null: false
    t.index ["slug"], name: "index_households_on_slug", unique: true
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

  create_table "location_reports", force: :cascade do |t|
    t.integer "household_id", null: false
    t.string "subject_type", null: false
    t.integer "subject_id", null: false
    t.integer "location_id"
    t.integer "reported_by_id"
    t.string "comment"
    t.datetime "created_at", null: false
    t.string "spot"
    t.boolean "penned", default: false, null: false
    t.index ["household_id", "subject_type", "id"], name: "index_location_reports_on_household_id_and_subject_type_and_id"
    t.index ["household_id"], name: "index_location_reports_on_household_id"
    t.index ["location_id"], name: "index_location_reports_on_location_id"
    t.index ["reported_by_id"], name: "index_location_reports_on_reported_by_id"
    t.index ["subject_type", "subject_id", "id"], name: "index_location_reports_on_subject_type_and_subject_id_and_id"
  end

  create_table "locations", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "created_by_id"
    t.string "name", null: false
    t.string "kind", default: "other", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_at"
    t.index ["created_by_id"], name: "index_locations_on_created_by_id"
    t.index ["household_id"], name: "index_locations_on_household_id"
  end

  create_table "notification_preferences", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "category", null: false
    t.boolean "push", null: false
    t.boolean "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "category"], name: "index_notification_preferences_on_user_id_and_category", unique: true
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

  create_table "pet_subscriptions", force: :cascade do |t|
    t.integer "pet_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.index ["pet_id", "user_id"], name: "index_pet_subscriptions_on_pet_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_pet_subscriptions_on_user_id"
  end

  create_table "pet_visits", force: :cascade do |t|
    t.integer "pet_id", null: false
    t.integer "household_id", null: false
    t.datetime "arrived_at", null: false
    t.datetime "left_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_pet_visits_on_household_id"
    t.index ["pet_id", "arrived_at"], name: "index_pet_visits_on_pet_id_and_arrived_at"
  end

  create_table "pets", force: :cascade do |t|
    t.integer "household_id", null: false
    t.integer "created_by_id"
    t.integer "home_id"
    t.string "name", null: false
    t.string "species"
    t.date "birthday"
    t.integer "meals_per_day", default: 2, null: false
    t.text "feeding_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "away_since"
    t.datetime "archived_at"
    t.boolean "visitor", default: false, null: false
    t.index ["created_by_id"], name: "index_pets_on_created_by_id"
    t.index ["home_id"], name: "index_pets_on_home_id"
    t.index ["household_id"], name: "index_pets_on_household_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.text "endpoint", null: false
    t.text "p256dh", null: false
    t.text "auth", null: false
    t.string "user_agent"
    t.datetime "last_used_at"
    t.string "last_error"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "residences", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "household_id", null: false
    t.integer "location_id", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_residences_on_household_id"
    t.index ["location_id"], name: "index_residences_on_location_id"
    t.index ["user_id"], name: "index_residences_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "task_assignments", force: :cascade do |t|
    t.integer "task_id", null: false
    t.integer "user_id", null: false
    t.string "status", default: "accepted", null: false
    t.string "conflict_note"
    t.datetime "responded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "user_id"], name: "index_task_assignments_on_task_id_and_user_id", unique: true
    t.index ["user_id", "status"], name: "index_task_assignments_on_user_id_and_status"
  end

  create_table "tasks", force: :cascade do |t|
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
    t.string "availability", default: "text", null: false
    t.string "place"
    t.date "due_on"
    t.datetime "started_at"
    t.boolean "private", default: false, null: false
    t.integer "location_id"
    t.boolean "follow_up", default: false, null: false
    t.datetime "finished_at"
    t.integer "finished_by_id"
    t.index ["created_by_id"], name: "index_tasks_on_created_by_id"
    t.index ["finished_by_id"], name: "index_tasks_on_finished_by_id"
    t.index ["household_id", "finished_at"], name: "index_tasks_on_household_id_and_finished_at"
    t.index ["household_id", "status", "due_on"], name: "index_tasks_on_household_id_and_status_and_due_on"
    t.index ["household_id", "status", "starts_at"], name: "index_tasks_on_household_id_and_status_and_starts_at"
    t.index ["location_id"], name: "index_tasks_on_location_id"
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
    t.date "birthday"
    t.string "work_availability", default: "text", null: false
    t.datetime "work_schedule_skipped_at"
    t.string "remember_token"
    t.integer "reminder_lead_minutes", default: 15, null: false
    t.integer "digest_hour", default: 7, null: false
    t.integer "quiet_hours_start"
    t.integer "quiet_hours_end"
    t.datetime "notifications_paused_until"
    t.index ["admin"], name: "index_users_on_admin"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["handle"], name: "index_users_on_handle", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "work_schedule_versions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.datetime "effective_at", null: false
    t.string "availability", null: false
    t.json "shifts", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_work_schedule_versions_on_user_id"
  end

  create_table "work_shifts", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "weekday", null: false
    t.string "from_time", null: false
    t.string "until_time", null: false
    t.string "place"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "weekday"], name: "index_work_shifts_on_user_id_and_weekday", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "days_off", "users"
  add_foreign_key "feedings", "households"
  add_foreign_key "feedings", "pets"
  add_foreign_key "feedings", "users", column: "fed_by_id"
  add_foreign_key "household_memberships", "households"
  add_foreign_key "household_memberships", "locations", column: "home_id"
  add_foreign_key "household_memberships", "users"
  add_foreign_key "invitations", "households"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "location_reports", "households"
  add_foreign_key "location_reports", "locations"
  add_foreign_key "location_reports", "users", column: "reported_by_id"
  add_foreign_key "locations", "households"
  add_foreign_key "locations", "users", column: "created_by_id"
  add_foreign_key "notification_preferences", "users"
  add_foreign_key "passkeys", "users"
  add_foreign_key "pet_subscriptions", "pets"
  add_foreign_key "pet_subscriptions", "users"
  add_foreign_key "pet_visits", "households"
  add_foreign_key "pet_visits", "pets"
  add_foreign_key "pets", "households"
  add_foreign_key "pets", "locations", column: "home_id"
  add_foreign_key "pets", "users", column: "created_by_id"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "residences", "households"
  add_foreign_key "residences", "locations"
  add_foreign_key "residences", "users"
  add_foreign_key "task_assignments", "tasks"
  add_foreign_key "task_assignments", "users"
  add_foreign_key "tasks", "households"
  add_foreign_key "tasks", "locations"
  add_foreign_key "tasks", "users", column: "created_by_id"
  add_foreign_key "tasks", "users", column: "finished_by_id"
  add_foreign_key "work_schedule_versions", "users"
  add_foreign_key "work_shifts", "users"
end
