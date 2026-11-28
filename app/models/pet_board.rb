# The "Where" page as a board: each place's pets, a house split into three
# zones (inside, outside, penned up). A house report with no spot goes in
# a plain zone of its own, so nobody's guessed into one.
class PetBoard
  Zone = Struct.new(:key, :label, :icon, :spot, :penned, :pets, keyword_init: true)

  HOUSE_ZONES = [
    { key: "inside", label: "Inside", icon: :house, spot: "inside", penned: false },
    { key: "outside", label: "Outside", icon: :trees, spot: "outside", penned: false },
    { key: "penned", label: "Penned up", icon: :fence, spot: "outside", penned: true }
  ].freeze

  attr_reader :places, :unplaced

  # pets: the ones on the page; statuses: Pet.statuses for them; locations:
  # the household's places, in display order.
  def initialize(pets, statuses, locations)
    reports = pets.to_h { |pet| [ pet, statuses.fetch(pet.id).report ] }
    @unplaced = pets.select { |pet| reports[pet]&.location_id.nil? }
    @places = locations.map { |location| [ location, zones_for(location, reports) ] }
  end

  private

  def zones_for(location, reports)
    here = reports.select { |_, report| report&.location_id == location.id }
    return [ Zone.new(key: "plain", pets: here.keys) ] unless location.house?

    zones = HOUSE_ZONES.map do |zone|
      pets = here.select { |_, report| report.spot == zone[:spot] && report.penned? == zone[:penned] }.keys
      Zone.new(**zone, pets: pets)
    end
    loose = here.select { |_, report| report.spot.nil? }.keys
    loose.any? ? [ Zone.new(key: "plain", label: "Here", icon: :map_pin, spot: nil, penned: false, pets: loose), *zones ] : zones
  end
end
