# One meal for one pet.
class Feeding < ApplicationRecord
  belongs_to :household
  belongs_to :pet
  belongs_to :fed_by, class_name: "User", optional: true

  validates :comment, length: { maximum: LocationReport::COMMENT_MAX }
  validate :pet_in_household, on: :create

  normalizes :comment, with: ->(comment) { comment.squish.presence }

  # "Today" is the viewer's day (Time.zone is set per request from the
  # browser; see ApplicationController#use_browser_time_zone).
  scope :today, -> { where(created_at: Time.zone.now.beginning_of_day..) }
  scope :recent, -> { order(id: :desc).includes(:fed_by) }

  after_commit { household.broadcast_refresh }

  private

  def pet_in_household
    errors.add(:pet, "must belong to this household") if pet && pet.household_id != household_id
  end
end
