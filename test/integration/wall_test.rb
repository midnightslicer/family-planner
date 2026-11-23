require "test_helper"

class WallTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @smiths = households(:smiths)
    @house = @smiths.locations.create!(name: "Big house", kind: "house")
    @yard = @smiths.locations.create!(name: "Yard", kind: "yard")
    @pool = @smiths.locations.create!(name: "Pool", kind: "pool")
  end

  setup { sign_in @admin }

  def wall = get(wall_path(@smiths.dashboard_token))

  test "a section for each occupied place, with everyone there and their cards" do
    LocationReport.create!(household: @smiths, subject: @member, location: @yard, reported_by: @member)
    rex = @smiths.pets.create!(name: "Rex")
    LocationReport.create!(household: @smiths, subject: rex, location: @yard, reported_by: @member)
    @smiths.pets.create!(name: "Tom")

    wall
    assert_response :success
    assert_select ".wall-place h2", text: "Yard"
    assert_select ".wall-place", text: /Yard/ do
      assert_select ".person-card", 1
      assert_select ".wall-pet", text: /Rex/
      assert_select ".wall-here .person-avatar", 2
    end
    assert_select ".wall-place h2", text: "Pool", count: 0
    assert_select ".wall-place h2", text: "Big house", count: 0
    # Nobody knows where Admin or Tom are.
    assert_select ".wall-place", text: /Somewhere else/ do
      assert_select ".person-card", 1
      assert_select ".wall-pet", text: /Tom/
    end
  end

  test "an event at a place puts its person in that place's section" do
    LocationReport.create!(household: @smiths, subject: @admin, location: @yard, reported_by: @admin)
    Task.create!(household: @smiths, title: "Client call", place: "Big house", assigned_to: @admin,
                 starts_at: 10.minutes.ago, ends_at: 50.minutes.from_now)
    wall
    assert_select ".wall-place", text: /Big house/ do
      assert_select "##{ActionView::RecordIdentifier.dom_id(@admin, :person_card)}"
    end
  end

  test "places follow the household's location order" do
    LocationReport.create!(household: @smiths, subject: @member, location: @pool, reported_by: @member)
    LocationReport.create!(household: @smiths, subject: @admin, location: @house, reported_by: @admin)
    wall
    assert_equal ["Big house", "Pool"], css_select(".wall-place h2").map(&:text)
  end
end
