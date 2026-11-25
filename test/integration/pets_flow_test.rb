require "test_helper"
require "turbo/broadcastable/test_helper"

class PetsFlowTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    @house = @smiths.locations.create!(name: "House", kind: "house", created_by: @admin)
    @yard = @smiths.locations.create!(name: "Yard", kind: "yard", created_by: @admin)
    @rex = @smiths.pets.create!(name: "Rex", species: "Dog", meals_per_day: 2, home: @house,
                                feeding_notes: "One cup at 7am and 6pm", created_by: @admin)
    @tom = @smiths.pets.create!(name: "Tom", species: "Cat", meals_per_day: 1, created_by: @admin)
    sign_in @member
  end

  test "the pets page shows each card" do
    get pets_path
    assert_response :success
    assert_select ".pet-card", 2
    assert_select ".pet-card", text: /Not reported yet/
    assert_select ".pet-card .status-chip", text: /Not fed yet today/
  end

  test "the feed and where screens group pets by type" do
    [new_feeding_path, new_pet_location_path].each do |path|
      get path
      assert_response :success
      assert_select ".pick-group", 2
      assert_select ".pick-group-title", text: "Cats"
      assert_select ".pick-group-title", text: "Dogs"
      assert_select ".picker-shortcuts", count: 0
    end
  end

  test "the pet form picks where it sleeps from photo tiles" do
    @rex.update!(home: @house)
    get edit_pet_path(@rex)
    assert_select ".pick-tile input[name='pet[home_id]']", count: 4 # Not set, House, Yard, New house
    assert_select ".pick-tile input[name='pet[home_id]'][value='#{@house.id}'][checked]"
    assert_select "select#pet_home_id", count: 0

    patch pet_path(@rex), params: { pet: { name: "Rex", meals_per_day: 2, home_id: "" } }
    assert_nil @rex.reload.home
  end

  test "a pet can have a custom type that then joins the menu" do
    post pets_path, params: { pet: { name: "Alma", species: Pet::NEW_KIND, new_species: "Alpaca", meals_per_day: 1 } }
    assert_equal "Alpaca", Pet.find_by!(name: "Alma").species

    get new_pet_path
    assert_select "select[name='pet[species]'] option", text: "Alpaca"
    assert_select "select[name='pet[species]'] option", text: "New type…"
    get edit_pet_path(Pet.find_by!(name: "Alma"))
    assert_select "select[name='pet[species]'] option[selected]", text: "Alpaca"
  end

  test "anyone can add a pet with feeding notes" do
    post pets_path, params: { pet: { name: "Bella", species: "Horse", birthday: "2020-04-02", meals_per_day: 3,
                                     feeding_notes: "Hay morning and night", home_id: @house.id } }
    bella = Pet.find_by!(name: "Bella")
    assert_redirected_to pet_path(bella)
    assert_equal @member, bella.created_by
    follow_redirect!
    assert_select ".feeding-notes", text: /Hay morning and night/
    assert_select ".task-meta", text: /Sleeps at House/
  end

  test "report several pets at once with a comment" do
    get new_pet_location_path(pet_ids: [@rex.id])
    assert_select "input[name='check_in[pet_ids][]'][value='#{@rex.id}'][checked]"
    assert_select "input[name='check_in[pet_ids][]'][value='#{@tom.id}']:not([checked])"

    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id, @tom.id], location_id: @yard.id, comment: "Gate shut" } }
    assert_redirected_to pets_path
    follow_redirect!
    assert_select ".flash-notice", text: /Rex and Tom are at Yard/
    assert_select ".pet-card .pet-where-name", text: "Yard", count: 2
    assert_select ".pet-card .report-comment", text: /Gate shut/
  end

  test "a report missing pets or a new place's name explains itself and keeps what was picked" do
    post pet_locations_path, params: { check_in: { location_id: @yard.id } }
    assert_response :unprocessable_content
    assert_select ".flash-alert", text: /Pick at least one pet/

    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: "new", new_location_name: "" } }
    assert_response :unprocessable_content
    assert_select ".flash-alert", text: /New location can't be blank/
    assert_select "input[name='check_in[pet_ids][]'][value='#{@rex.id}'][checked]"
    assert_select "input[name='check_in[location_id]'][value='new'][checked]"
  end

  test "feeding shows the notes and counts meals" do
    get new_feeding_path
    assert_select ".feeding-notes", text: /One cup at 7am/

    post feedings_path, params: { check_in: { pet_ids: [@rex.id, @tom.id] } }
    follow_redirect!
    assert_select ".flash-notice", text: /Fed Rex and Tom/
    assert_equal 1, @rex.feedings.count
    assert_equal :fed, @tom.status.fed_state
  end

  test "the dashboard shows pets with where they are and whether they've eaten" do
    LocationReport.create!(household: @smiths, subject: @rex, location: @yard, reported_by: @admin)
    get root_path
    assert_select ".pet-card", 2
    # Under the Yard heading, so the card says how fresh that is, not where.
    assert_select "##{dom_id(@yard, :board_place)} ##{dom_id(@rex, :pet_card)} .pet-where small", text: /Seen/
    assert_select "##{dom_id(@rex, :pet_card)} .pet-where-name", count: 0
    assert_select ".pet-card button", text: "Fed"
  end

  test "pets are on the wall, read-only, with where they are and whether they've eaten" do
    LocationReport.create!(household: @smiths, subject: @rex, location: @yard, reported_by: @admin)
    Feeding.create!(household: @smiths, pet: @rex, fed_by: @admin)
    get wall_path(@smiths.slug)
    assert_response :success
    assert_select ".wall-pet", 2
    assert_select ".wall-pet", text: /Rex.*Fed 1 of 2/m
    assert_select ".wall-pet button, .wall-pet form", count: 0
  end

  test "at a house you can say inside or outside, and it shows" do
    get new_pet_location_path
    assert_select ".spot-field input[name='check_in[spot]'][value='outside']"
    assert_select ".pick-house input[value='#{@house.id}']"

    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: @house.id, spot: "outside" } }
    follow_redirect!
    assert_select ".flash-notice", text: "Rex is at House (outside)."
    assert_select "##{dom_id(@rex, :pet_card)} .pet-where-name", text: "House"
    assert_select "##{dom_id(@rex, :pet_card)} .spot-chip.is-outside", text: "Outside"
  end

  test "outside at a house you can say a pet is penned up, and it shows" do
    get new_pet_location_path
    assert_select ".pen-field input[type=checkbox][name='check_in[penned]']"

    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: @house.id, spot: "outside", penned: "1" } }
    follow_redirect!
    assert_select ".flash-notice", text: "Rex is at House (outside, penned up)."
    assert_select "##{dom_id(@rex, :pet_card)} .pet-where-name", text: "House"
    assert_select "##{dom_id(@rex, :pet_card)} .spot-chip.is-penned", text: "Penned up"

    # The dashboard groups it under House, so the card shows the chip instead.
    get root_path
    assert_select "##{dom_id(@house, :board_place)} ##{dom_id(@rex, :pet_card)} .spot-chip.is-penned", text: "Penned up"
  end

  test "inside, outside and penned up only count at a house, and penned up only outside" do
    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: @yard.id, spot: "inside", penned: "1" } }
    assert_nil @rex.status.report.spot
    assert_not @rex.status.report.penned?
    follow_redirect!
    assert_select ".flash-notice", text: "Rex is at #{@yard.name}."

    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: @house.id, spot: "inside", penned: "1" } }
    assert_not @rex.status.report.penned?
    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: @house.id, penned: "1" } }
    assert_not @rex.status.report.penned?
    follow_redirect!
    assert_select ".flash-notice", text: "Rex is at House."
  end

  test "a pet we sit can be not here: off the board, the wall and the pickers, and back with one tap" do
    # Only for pets we sit.
    get pet_path(@rex)
    assert_select "form[action='#{away_pet_path(@rex)}']", count: 0
    post away_pet_path(@rex)
    assert_redirected_to pet_path(@rex)
    assert_not @rex.reload.away?

    @rex.update!(visitor: true)
    get pet_path(@rex)
    assert_select "form[action='#{away_pet_path(@rex)}']", 1
    post away_pet_path(@rex)
    assert @rex.reload.away?

    get pets_path
    assert_select ".pet-card", 1
    assert_select ".away-list", text: /Rex/
    get root_path
    assert_select ".pet-card .person-name", text: "Rex", count: 0
    get new_feeding_path
    assert_select "input[name='check_in[pet_ids][]'][value='#{@rex.id}']", count: 0
    get new_pet_location_path
    assert_select "input[name='check_in[pet_ids][]'][value='#{@rex.id}']", count: 0
    get wall_path(@smiths.slug)
    assert_select ".wall-pet", text: /Rex/, count: 0

    # Even posted directly, an away pet isn't fed or moved.
    post feedings_path, params: { check_in: { pet_ids: [@rex.id] } }
    assert_equal 0, @rex.feedings.count

    get pet_path(@rex)
    assert_select ".away-banner", text: /Rex isn't here right now/
    post back_pet_path(@rex)
    assert_not @rex.reload.away?
    get root_path
    assert_select ".pet-card .person-name", text: "Rex"
  end

  test "you can take back your own feeding but not someone else's" do
    mine = Feeding.create!(household: @smiths, pet: @rex, fed_by: @member)
    theirs = Feeding.create!(household: @smiths, pet: @rex, fed_by: @admin)
    delete feeding_path(theirs)
    assert_response :forbidden
    delete feeding_path(mine)
    assert_not Feeding.exists?(mine.id)
  end

  test "only whoever added a pet (or an admin) can remove it" do
    delete pet_path(@rex)
    assert_response :forbidden
    sign_in @admin
    delete pet_path(@rex)
    assert @rex.reload.archived?
  end

  test "removing a pet or a place archives it: gone from the app, history kept" do
    LocationReport.create!(household: @smiths, subject: @rex, location: @yard, reported_by: @admin)
    feeding = Feeding.create!(household: @smiths, pet: @rex, fed_by: @admin)
    sign_in @admin
    delete pet_path(@rex)
    delete location_path(@yard)

    get pets_path
    assert_select ".pet-card .person-name", text: "Rex", count: 0
    get pet_path(@rex)
    assert_response :not_found
    get locations_path
    assert_select ".place-card h2", text: "Yard", count: 0
    get new_pet_location_path
    assert_select ".pick-place .pick-name", text: "Yard", count: 0

    assert Feeding.exists?(feeding.id)
    report = LocationReport.where(subject: @rex).sole
    assert_equal "Yard", report.location.name, "the report still knows the place"

    # The name is free for a new place.
    post locations_path, params: { location: { name: "Yard", kind: "yard" } }
    assert_equal 2, Location.where(name: "Yard").count
  end

  test "another household's pets and locations are not found" do
    other = Household.create!(name: "Others")
    stray = other.pets.create!(name: "Stray")
    place = other.locations.create!(name: "Theirs")
    get pet_path(stray)
    assert_response :not_found
    get edit_location_path(place)
    assert_response :not_found
  end

  test "a new place can be added right in the report form; typing an existing one's name reuses it" do
    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id, @tom.id], location_id: "new", new_location_name: " Pool " } }
    pool = @smiths.locations.find_by!(name: "Pool")
    assert_equal @member, pool.created_by
    assert_equal [pool, pool], [@rex, @tom].map { |pet| pet.status.report.location }

    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: "new", new_location_name: "yard" } }
    assert_equal 3, @smiths.locations.count
    assert_equal @yard, @rex.status.report.location
  end

  test "a pet's house can be added in the pet form without leaving it" do
    post pets_path, params: { pet: { name: "Bella", meals_per_day: 2, home_id: "new", new_home_name: "Barn house" } }
    bella = Pet.find_by!(name: "Bella")
    assert_equal "Barn house", bella.home.name
    assert bella.home.house?
  end

  test "a pet's photo saves; one saved on crop stays on the edit page, saving the form goes to the pet" do
    post pets_path, params: { pet: { name: "Bella", meals_per_day: 2, home_id: "",
                                     photo: fixture_file_upload("avatar.png", "image/png") } }
    assert Pet.find_by!(name: "Bella").photo_saved?

    patch pet_path(@rex), params: { photo_autosave: "1", pet: { photo: fixture_file_upload("avatar.png", "image/png") } }
    assert_redirected_to edit_pet_path(@rex)
    assert @rex.reload.photo_saved?

    patch pet_path(@rex), params: { pet: { name: "Rex" } }
    assert_redirected_to pet_path(@rex)
  end

  test "following a pet notifies you when someone else feeds or moves it" do
    post pet_subscription_path(@rex)
    assert @rex.followed_by?(@member)

    sign_in @admin
    assert_turbo_stream_broadcasts [@member, :notifications], count: 1 do
      post feedings_path, params: { check_in: { pet_ids: [@rex.id, @tom.id], comment: "half a cup" } }
    end
    # Not for your own reports.
    sign_in @member
    assert_turbo_stream_broadcasts [@member, :notifications], count: 0 do
      post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: @yard.id } }
    end

    delete pet_subscription_path(@rex)
    assert_not @rex.followed_by?(@member)
  end
end
