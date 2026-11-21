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

  test "the nav has a Pets tab and the pets page shows each card" do
    get pets_path
    assert_response :success
    assert_select ".nav-links a[aria-current=page]", text: "Pets"
    assert_select ".pet-card", 2
    assert_select ".pet-card", text: /Not reported yet/
    assert_select ".pet-card .status-chip", text: /Not fed yet today/
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

  test "a report with nothing picked explains what's missing" do
    post pet_locations_path, params: { check_in: { location_id: @yard.id } }
    assert_response :unprocessable_content
    assert_select ".flash-alert", text: /Pick at least one pet/
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
    get dashboard_path
    assert_select ".pet-card", 2
    assert_select "##{ActionView::RecordIdentifier.dom_id(@rex, :pet_card)} .pet-where-name", text: "Yard"
    assert_select ".pet-card button", text: "Fed"
  end

  test "pets are on the wall, read-only, with where they are and whether they've eaten" do
    LocationReport.create!(household: @smiths, subject: @rex, location: @yard, reported_by: @admin)
    Feeding.create!(household: @smiths, pet: @rex, fed_by: @admin)
    sign_out @member
    get wall_path(@smiths.dashboard_token)
    assert_response :success
    assert_select ".wall-pet", 2
    assert_select ".wall-pet", text: /Rex.*Fed 1 of 2/m
    assert_select ".wall-pet button, .wall-pet form", count: 0
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
    assert_not Pet.exists?(@rex.id)
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

  test "a new place can be added right in the report form, keeping the picked pets" do
    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id, @tom.id], location_id: "new", new_location_name: " Pool " } }
    pool = @smiths.locations.find_by!(name: "Pool")
    assert_equal @member, pool.created_by
    assert_equal [pool, pool], [@rex, @tom].map { |pet| pet.status.report.location }
  end

  test "a new place with no name explains itself and keeps what was picked" do
    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: "new", new_location_name: "" } }
    assert_response :unprocessable_content
    assert_select ".flash-alert", text: /New location can't be blank/
    assert_select "input[name='check_in[pet_ids][]'][value='#{@rex.id}'][checked]"
    assert_select "input[name='check_in[location_id]'][value='new'][checked]"
  end

  test "typing an existing place's name reuses it" do
    post pet_locations_path, params: { check_in: { pet_ids: [@rex.id], location_id: "new", new_location_name: "yard" } }
    assert_equal 2, @smiths.locations.count
    assert_equal @yard, @rex.status.report.location
  end

  test "a pet's house can be added in the pet form without leaving it" do
    post pets_path, params: { pet: { name: "Bella", meals_per_day: 2, home_id: "new", new_home_name: "Barn house" } }
    bella = Pet.find_by!(name: "Bella")
    assert_equal "Barn house", bella.home.name
    assert bella.home.house?
  end

  test "a pet's photo saves" do
    post pets_path, params: { pet: { name: "Bella", meals_per_day: 2, home_id: "",
                                     photo: fixture_file_upload("avatar.png", "image/png") } }
    assert Pet.find_by!(name: "Bella").photo_saved?
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
