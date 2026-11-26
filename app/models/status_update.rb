# A status someone set by hand (Free, Text only, Do not disturb). For LASTS
# it wins over whatever their work hours and events say about how
# reachable they are, then they're back to those. Append-only: the newest
# row per person is what counts.
class StatusUpdate < ApplicationRecord
  LASTS = 12.hours

  belongs_to :user

  enum :availability, { free: "free", text: "text", busy: "busy" }, prefix: :availability, validate: true

  before_validation on: :create do
    self.expires_at ||= Time.current + LASTS
  end

  # { user_id => StatusUpdate } for whoever has one in force at `now`.
  def self.active_for(user_ids, now = Time.current)
    newest = where(user_id: user_ids).group(:user_id).select("MAX(id)")
    where(id: newest).where("expires_at > ?", now).index_by(&:user_id)
  end

  def self.active_for_user(user, now = Time.current) = active_for([ user.id ], now)[user.id]

  # Duck-types with a task for availability_chip.
  def title = nil
end
