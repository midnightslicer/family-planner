# Who is where right now, as sections: one per location someone (or some
# pet) is at, busiest first (most people and pets; ties by the household's
# location order), then everyone whose place is unknown or not one of the
# locations, always last. A person is where their current
# event or work hours put them, unless they've said where they are since
# it started (Household#member_statuses drops :at then); a pet where it
# was last reported. `sections(first: person)` puts the section that
# person is in on top (the dashboard: where you are, then the rest),
# "Somewhere else" included.
#
#   Whereabouts.new(household.places, members:, statuses:, pets:, pet_statuses:).sections
#   # => [Section(location, people, pets), ..., Section(nil, people, pets)]
class Whereabouts
  Section = Struct.new(:location, :people, :pets) do
    def everyone = people + pets
  end

  # `places`: the household's locations in display order (Household#places).
  def initialize(places, members:, statuses:, pets:, pet_statuses:)
    @locations = places.to_a
    @members = members.to_a
    @statuses = statuses
    @pets = pets.to_a
    @pet_statuses = pet_statuses
  end

  def sections(first: nil)
    all = ordered
    mine = first && all.index { |section| section.people.include?(first) }
    mine ? [all[mine], *all[0...mine], *all[(mine + 1)..]] : all
  end

  private

  def ordered
    people = @members.group_by { |member| person_location_id(member) }
    pets = @pets.group_by { |pet| pet_location_id(pet) }

    placed = @locations.filter_map do |location|
      section = Section.new(location, people.fetch(location.id, []), pets.fetch(location.id, []))
      section unless section.everyone.empty?
    end
    # Busiest first; sort_by isn't stable, so the place order breaks ties.
    placed = placed.each_with_index.sort_by { |section, index| [-section.everyone.size, index] }.map(&:first)
    known = @locations.to_set(&:id)
    elsewhere = Section.new(nil, @members.reject { |m| known.include?(person_location_id(m)) },
                            @pets.reject { |p| known.include?(pet_location_id(p)) })
    elsewhere.everyone.empty? ? placed : placed + [elsewhere]
  end

  def person_location_id(member)
    status = @statuses[member.id]
    status[:at]&.id || status[:location]&.location_id
  end

  def pet_location_id(pet)
    @pet_statuses[pet.id]&.report&.location_id
  end
end
