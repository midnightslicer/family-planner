# A household pet. Anyone in the household can add one, say where it is
# (LocationReport) and record that it was fed (Feeding).
class Pet < ApplicationRecord
  include SmallPhoto

  MAX_MEALS = 8
  KINDS = %w[Dog Cat Horse Rabbit Bird Chicken Goat Fish].freeze
  # The type menu's "New type…" value; the name comes in a box beside it.
  NEW_KIND = "new".freeze

  belongs_to :household
  belongs_to :created_by, class_name: "User", optional: true
  # Where it sleeps.
  belongs_to :home, class_name: "Location", optional: true
  has_many :feedings, dependent: :delete_all
  has_many :location_reports, as: :subject, dependent: :delete_all
  has_many :subscriptions, class_name: "PetSubscription", dependent: :delete_all
  # Every stretch it's been here (dogs we sit come and go).
  has_many :visits, -> { order(:arrived_at) }, class_name: "PetVisit", dependent: :delete_all
  has_many :subscribers, through: :subscriptions, source: :user

  small_photo :photo

  validates :name, presence: true, length: { maximum: 40 }
  validates :species, length: { maximum: 30 }
  validates :meals_per_day, numericality: { only_integer: true, in: 0..MAX_MEALS }
  validates :feeding_notes, length: { maximum: 1_000 }
  validate :birthday_not_in_future
  validate :home_in_household
  validate -> { Location.new_location_errors(home).each { |message| errors.add(:base, message) } }

  normalizes :name, :species, with: ->(value) { value.squish.presence }

  scope :by_name, -> { order(:name) }
  # Pets that come and go (dog-sitting) are marked away rather than deleted:
  # off the board, the wall and the pickers, back with one tap.
  scope :here, -> { where(away_since: nil) }
  scope :away, -> { where.not(away_since: nil) }

  after_create { visits.create!(household: household, arrived_at: created_at) }
  after_commit { household.broadcast_refresh }

  # The type menu: the usual ones, then whatever else this household has
  # added (custom types), plus `current` so editing never drops a type.
  def self.kinds_for(household, current = nil)
    used = household.all_pets.where.not(species: [nil, ""]).distinct.pluck(:species)
    (KINDS + [*used, current].compact_blank).uniq { |kind| kind.downcase }.sort_by(&:downcase)
  end

  # For the dashboard and pet cards, everything in a few queries instead of a
  # few per pet: { pet_id => PetStatus }.
  def self.statuses(household, pets)
    pets = pets.to_a
    ids = pets.map(&:id)
    reports = LocationReport.latest_for(household, "Pet", ids, preload: [:location, :reported_by])
    today = Feeding.where(pet_id: ids).today
    fed_counts = today.group(:pet_id).count
    last_fed = Feeding.where(id: Feeding.where(pet_id: ids).group(:pet_id).select("MAX(id)"))
                      .includes(:fed_by).index_by(&:pet_id)

    pets.to_h do |pet|
      [pet.id, PetStatus.new(pet: pet, report: reports[pet.id], fed_today: fed_counts.fetch(pet.id, 0), last_feeding: last_fed[pet.id])]
    end
  end

  # "Remove": gone from the app, kept (with its reports, feedings and
  # visits) for history.
  def archive!
    transaction do
      close_visit
      update!(archived_at: Time.current)
    end
  end

  # "Not here right now": off the board until it's back; the visit ends.
  def leave!
    return false if away?

    transaction do
      close_visit
      update!(away_since: Time.current)
    end
    true
  end

  # Back here: a new visit starts.
  def arrive!
    return false unless away?

    transaction do
      update!(away_since: nil)
      visits.create!(household: household, arrived_at: Time.current)
    end
    true
  end

  def archived?
    archived_at.present?
  end

  def away?
    away_since.present?
  end

  def followed_by?(user)
    subscriptions.exists?(user_id: user.id)
  end

  def status
    self.class.statuses(household, [self]).fetch(id)
  end

  private

  def close_visit
    visits.open.update_all(left_at: Time.current, updated_at: Time.current)
  end

  def birthday_not_in_future
    errors.add(:birthday, "can't be in the future") if birthday && birthday > Date.current
  end

  def home_in_household
    return if home.nil? || home.new_record? || household.blank?

    errors.add(:home, "must be one of this household's locations") unless home.household_id == household.id
  end
end
