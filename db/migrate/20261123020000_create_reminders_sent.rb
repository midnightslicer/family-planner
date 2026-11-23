# One row per reminder sent (ReminderJob), written before it's sent, so a
# second tick, a retry or a second worker can't send it twice. Event
# reminders key on the occurrence's start (a retimed or repeated event gets
# its own); the morning to-do digest has no task and keys on the day.
class CreateRemindersSent < ActiveRecord::Migration[8.1]
  def change
    create_table :reminders_sent do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :household, null: false, foreign_key: { on_delete: :cascade }
      t.references :task, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.datetime :occurrence_starts_at, null: false
      t.datetime :created_at, null: false
    end
    # COALESCE: SQLite treats NULLs as distinct in a unique index, which
    # would let digests (no task) through twice.
    add_index :reminders_sent, "user_id, household_id, kind, COALESCE(task_id, 0), occurrence_starts_at",
              unique: true, name: "index_reminders_sent_once"
  end
end
