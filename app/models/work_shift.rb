# One weekday of someone's regular work hours. A day with no row is a day
# they don't work. `until_time` before `from_time` means it runs past
# midnight.
class WorkShift < ApplicationRecord
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  # Where people usually work, offered before the household's houses. Just
  # labels: unlike locations, nobody can be reported "at" them.
  PLACES = %w[Office Remote].freeze

  belongs_to :user

  validates :weekday, inclusion: { in: 0..6 }, uniqueness: { scope: :user_id }
  validates :from_time, :until_time, format: { with: TIME_FORMAT, message: "must be a time like 09:00" }
  validates :place, length: { maximum: 60 }

  normalizes :place, with: ->(place) { place.squish.presence }
end
