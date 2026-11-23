# A reminder that has gone out (see ReminderJob). Claiming one is the
# insert: only the caller whose insert succeeds sends it.
class ReminderSent < ApplicationRecord
  self.table_name = "reminders_sent"

  KINDS = %w[event digest].freeze

  belongs_to :user
  belongs_to :household
  belongs_to :task, optional: true

  validates :kind, inclusion: { in: KINDS }

  # true if this call claimed it, false if it was already sent.
  def self.claim(**attributes)
    insert!(attributes.merge(created_at: Time.current))
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
