# A place in a household that pets and people can be: a house, the yard, a
# pasture... Anyone in the household can add one.
class Location < ApplicationRecord
  include SmallPhoto

  KINDS = %w[house yard pasture pool other].freeze

  belongs_to :household
  belongs_to :created_by, class_name: "User", optional: true
  has_many :location_reports, dependent: :nullify
  has_many :tasks, dependent: :nullify
  has_many :residents, class_name: "HouseholdMembership", foreign_key: :home_id, inverse_of: :home, dependent: :nullify
  has_many :pets_living_here, class_name: "Pet", foreign_key: :home_id, inverse_of: :home, dependent: :nullify

  small_photo :photo

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: :household_id, case_sensitive: false, conditions: -> { where(archived_at: nil) } }
  validates :kind, inclusion: { in: KINDS }

  normalizes :name, with: ->(name) { name.squish }

  # Houses first (they're where pets sleep), then alphabetical.
  scope :in_display_order, -> { in_order_of(:kind, KINDS).order(:name) }

  after_commit { household.broadcast_refresh }

  # What a location picker sent: an existing id, or "new" plus a name typed
  # right there (so nobody has to leave a half-filled form to add a place).
  # A name that already exists is reused; otherwise the new location is
  # returned unsaved, and saves with the record that points at it.
  NEW = "new".freeze

  def self.chosen(household, id, new_name: nil, kind: "other", created_by: nil)
    return household.locations.find_by(id: id) unless id.to_s == NEW

    name = new_name.to_s.squish
    household.locations.where("lower(name) = ?", name.downcase).first ||
      household.locations.new(name: name, kind: kind, created_by: created_by)
  end

  # For records that save a new location along with themselves: its errors,
  # in words that make sense on that record's form.
  def self.new_location_errors(location)
    return [] unless location&.new_record?
    return [] if location.valid?

    location.errors.map { |error| "New location #{error.message}" }
  end

  def archived?
    archived_at.present?
  end

  # "Remove": gone from the app, kept for history. Nobody lives or sleeps
  # there any more (the history of that is in Residence).
  def archive!
    transaction do
      update!(archived_at: Time.current)
      pets_living_here.update_all(home_id: nil)
      residents.each { |membership| membership.update!(home: nil) }
    end
  end

  def house?
    kind == "house"
  end
end
