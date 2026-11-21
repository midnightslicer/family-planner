# A day, or run of days, someone is off work (vacation, sick, a holiday).
class DayOff < ApplicationRecord
  self.table_name = "days_off"

  belongs_to :user

  validates :starts_on, :ends_on, presence: true
  validates :note, length: { maximum: 60 }
  validate :ends_after_start

  normalizes :note, with: ->(note) { note.squish.presence }

  scope :covering, ->(date) { where("starts_on <= :date AND ends_on >= :date", date: date) }
  scope :upcoming, ->(from = Date.current) { where(ends_on: from..).order(:starts_on) }

  def covers?(date)
    starts_on <= date && date <= ends_on
  end

  def single_day?
    starts_on == ends_on
  end

  private

  def ends_after_start
    errors.add(:ends_on, "must be on or after the first day off") if starts_on && ends_on && ends_on < starts_on
  end
end
