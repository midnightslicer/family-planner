# "<pet or person> is at <location>", with an optional short comment. The
# newest report for a subject is where it is now, until someone reports it
# somewhere else. Pets can be reported by anyone in the household; people
# only report themselves (enforced by the controllers, which never take a
# person from params).
class LocationReport < ApplicationRecord
  SUBJECT_TYPES = %w[Pet User].freeze
  COMMENT_MAX = 140

  belongs_to :household
  belongs_to :subject, polymorphic: true
  belongs_to :location, optional: true
  belongs_to :reported_by, class_name: "User", optional: true

  validates :subject_type, inclusion: { in: SUBJECT_TYPES }
  validates :location, presence: true, on: :create
  SPOTS = %w[inside outside].freeze

  validates :comment, length: { maximum: COMMENT_MAX }
  validates :spot, inclusion: { in: SPOTS }, allow_nil: true
  validate :everything_in_household, on: :create
  validate -> { Location.new_location_errors(location).each { |message| errors.add(:base, message) } }, on: :create

  normalizes :comment, with: ->(comment) { comment.squish.presence }
  normalizes :spot, with: ->(spot) { spot.strip.downcase.presence }
  # Inside/outside only means something at a house; penned up only means
  # something outdoors (outside at a house, or anywhere that isn't one).
  before_validation do
    self.spot = nil unless location&.house?
    self.penned = false unless pennable?
  end

  after_commit :broadcast

  # The newest report per subject: { subject_id => LocationReport }.
  def self.latest_for(household, subject_type, subject_ids)
    newest = where(household_id: household.id, subject_type: subject_type, subject_id: subject_ids)
             .group(:subject_id).select("MAX(id)")
    where(id: newest).includes(:location, :reported_by).index_by(&:subject_id)
  end

  def self.recent
    order(id: :desc).includes(:location, :reported_by)
  end

  def pennable?
    location.present? && (!location.house? || spot == "outside")
  end

  # "outside, penned up" / "inside" / "penned up" / nil.
  def spot_words
    [spot, ("penned up" if penned?)].compact.join(", ").presence
  end

  private

  def everything_in_household
    return if household.blank?

    if location && location.household_id != household_id
      errors.add(:location, "must be one of this household's locations")
    end
    in_household =
      case subject
      when Pet then subject.household_id == household_id
      when User then subject.member_of?(household)
      end
    errors.add(:subject, "must belong to this household") unless in_household
  end

  def broadcast
    if subject_type == "User"
      household.broadcast_member_cards([subject_id])
    end
    household.broadcast_refresh
  rescue StandardError => error
    Rails.logger.warn("Live update failed for location report #{id}: #{error.class}: #{error.message}")
  end
end
