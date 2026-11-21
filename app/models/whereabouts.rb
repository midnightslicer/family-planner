# Who is where right now, as sections: one per location someone (or some
# pet) is at, in the household's location order, then everyone whose place
# is unknown or not one of the locations. A person is where their current
# event or work hours put them, else where they last said; a pet where it
# was last reported.
#
#   Whereabouts.new(household, members:, statuses:, pets:, pet_statuses:).sections
#   # => [Section(location, people, pets), ..., Section(nil, people, pets)]
class Whereabouts
  Section = Struct.new(:location, :people, :pets) do
    def everyone = people + pets
  end

  def initialize(household, members:, statuses:, pets:, pet_statuses:)
    @household = household
    @members = members.to_a
    @statuses = statuses
    @pets = pets.to_a
    @pet_statuses = pet_statuses
  end

  def sections
    locations = @household.locations.in_display_order.with_attached_photo.to_a
    people = @members.group_by { |member| person_location_id(member) }
    pets = @pets.group_by { |pet| @pet_statuses[pet.id]&.report&.location_id }

    placed = locations.filter_map do |location|
      section = Section.new(location, people.fetch(location.id, []), pets.fetch(location.id, []))
      section unless section.everyone.empty?
    end
    known = locations.map(&:id)
    elsewhere = Section.new(nil, @members.reject { |m| known.include?(person_location_id(m)) },
                            @pets.reject { |p| known.include?(@pet_statuses[p.id]&.report&.location_id) })
    elsewhere.everyone.empty? ? placed : placed + [elsewhere]
  end

  private

  def person_location_id(member)
    status = @statuses[member.id]
    status[:at]&.id || status[:location]&.location_id
  end
end
