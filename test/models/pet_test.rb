require "test_helper"

class PetTest < ActiveSupport::TestCase
  include ActionView::Helpers::TextHelper
  include PetsHelper

  setup do
    @smiths = households(:smiths)
    @member = users(:member)
    @house = @smiths.locations.create!(name: "House", kind: "house")
    @yard = @smiths.locations.create!(name: "Yard", kind: "yard")
    @rex = @smiths.pets.create!(name: "Rex", species: "Dog", meals_per_day: 2, home: @house)
    @tom = @smiths.pets.create!(name: "Tom", species: "Cat", meals_per_day: 1)
  end

  test "a check-in reports several pets at once and the newest report is where they are" do
    LocationReport.create!(household: @smiths, subject: @rex, location: @house, reported_by: @member)
    check_in = PetCheckIn.new(household: @smiths, actor: @member, kind: "location",
                              pet_ids: [@rex.id, @tom.id], location_id: @yard.id, comment: "Gate shut")
    assert check_in.save
    assert_equal "Rex and Tom are at Yard.", check_in.summary

    statuses = Pet.statuses(@smiths, [@rex, @tom])
    assert_equal "Yard", statuses[@rex.id].report.location.name
    assert_equal "Gate shut", statuses[@tom.id].report.comment
  end

  test "a location check-in needs pets and a place from this household" do
    other = Household.create!(name: "Others")
    their_place = other.locations.create!(name: "Theirs")
    check_in = PetCheckIn.new(household: @smiths, actor: @member, kind: "location", pet_ids: [@rex.id], location_id: their_place.id)
    assert_not check_in.save
    assert_includes check_in.errors.full_messages, "Pick where they are."

    their_pet = other.pets.create!(name: "Stray")
    check_in = PetCheckIn.new(household: @smiths, actor: @member, kind: "feeding", pet_ids: [their_pet.id])
    assert_not check_in.save
    assert_includes check_in.errors.full_messages, "Pick at least one pet."
    assert_equal 0, Feeding.count
  end

  test "fed status counts today's meals against meals per day" do
    assert_equal :hungry, @rex.status.fed_state
    Feeding.create!(household: @smiths, pet: @rex, fed_by: @member, created_at: 1.day.ago)
    assert_equal :hungry, @rex.status.fed_state

    PetCheckIn.new(household: @smiths, actor: @member, kind: "feeding", pet_ids: [@rex.id]).save
    status = @rex.status
    assert_equal :partly, status.fed_state
    assert_equal 1, status.fed_today

    PetCheckIn.new(household: @smiths, actor: @member, kind: "feeding", pet_ids: [@rex.id]).save
    assert_equal :fed, @rex.status.fed_state
  end

  test "a pet nobody feeds has no fed status" do
    @tom.update!(meals_per_day: 0)
    assert_not @tom.status.tracks_meals?
  end

  test "deleting a location keeps the history but says somewhere else" do
    LocationReport.create!(household: @smiths, subject: @rex, location: @yard, reported_by: @member)
    @yard.destroy
    report = @rex.status.report
    assert_nil report.location
    assert_nil @rex.reload.home_id unless @rex.home_id == @house.id
  end

  test "ages read naturally" do
    today = Date.new(2026, 11, 21)
    assert_equal "3 years", age_in_words(Date.new(2023, 6, 1), today)
    assert_equal "1 year, 2 months", age_in_words(Date.new(2025, 9, 10), today)
    assert_equal "1 year", age_in_words(Date.new(2025, 11, 21), today)
    assert_equal "4 months", age_in_words(Date.new(2026, 6, 22), today)
    assert_equal "3 weeks", age_in_words(Date.new(2026, 10, 30), today)
    assert_equal "newborn", age_in_words(Date.new(2026, 11, 19), today)
    assert_nil age_in_words(nil, today)
  end

  test "birthdays can't be in the future" do
    @rex.birthday = Date.tomorrow
    assert_not @rex.valid?
  end
end
