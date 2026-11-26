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

  def wall = get(wall_path(@smiths.slug))

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

  test "the wall drifts through the family's colours" do
    @member.update!(color: @admin.color)
    wall
    assert_select "body.kiosk[data-controller='wall-drift']"
    colours = JSON.parse(css_select("body").first["data-wall-drift-colors-value"])
    assert_equal [ @admin.color ], colours # each colour once
  end

  test "a pet's inside, outside or penned up shows as a chip" do
    rex = @smiths.pets.create!(name: "Rex")
    tom = @smiths.pets.create!(name: "Tom")
    bo = @smiths.pets.create!(name: "Bo")
    LocationReport.create!(household: @smiths, subject: rex, location: @house, spot: "inside", reported_by: @member)
    LocationReport.create!(household: @smiths, subject: tom, location: @house, spot: "outside", penned: true, reported_by: @member)
    LocationReport.create!(household: @smiths, subject: bo, location: @house, spot: "outside", reported_by: @member)
    wall
    assert_select ".wall-pet", text: /Rex/ do
      assert_select ".spot-chip.is-inside", text: "Inside"
    end
    assert_select ".wall-pet", text: /Tom/ do
      assert_select ".spot-chip.is-penned", text: "Penned up"
    end
    assert_select ".wall-pet", text: /Bo/ do
      assert_select ".spot-chip.is-outside", text: "Outside"
    end
  end

  test "an event at a place puts its person in that place's section" do
    # Said they were in the yard before the call began: the call, newer, wins.
    travel_to(20.minutes.ago) { LocationReport.create!(household: @smiths, subject: @admin, location: @yard, reported_by: @admin) }
    Task.create!(household: @smiths, title: "Client call", place: "Big house", assigned_to: @admin,
                 starts_at: 10.minutes.ago, ends_at: 50.minutes.from_now)
    wall
    assert_select ".wall-place", text: /Big house/ do
      assert_select card(@admin)
    end
  end

  test "saying where you are mid-shift moves you; a shift that starts later still takes you to work" do
    @smiths.update!(time_zone: "Central Time (US & Canada)")
    office = @smiths.locations.create!(name: "Office", kind: "other")
    @admin.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00", place: "Office")
    admin_card = card(@admin)

    # Reported at the house before work: work's place wins once the shift is on.
    travel_to(Time.utc(2026, 11, 23, 14, 0)) { LocationReport.create!(household: @smiths, subject: @admin, location: @house, reported_by: @admin) }
    travel_to Time.utc(2026, 11, 23, 16, 0) do # 10 AM, mid-shift
      wall
      assert_select ".wall-place", text: /Office/ do
        assert_select admin_card
      end

      # Now they say they're in the yard: that's newer, so it wins.
      sign_in @admin
      post locate_me_path, params: { location_report: { location_id: @yard.id } }
      wall
      assert_select ".wall-place", text: /Yard/ do
        assert_select admin_card
        # The shift's place no longer says where they are.
        assert_select "#{admin_card} .person-now", text: "Work · until 5 PM"
      end
      assert_select ".wall-place h2", text: office.name, count: 0
      get tasks_path
      assert_select ".day-where", text: /Yard/
      assert_select ".now-banner small", text: "until 5 PM"
      get root_path
      assert_select "#{admin_card} .person-now", text: "Work · until 5 PM"
      get tasks_path(person: "family")
      assert_select ".family-now .person-now", text: "Work · until 5 PM"
    end
  end

  test "a pet can be left off the wall, and stays everywhere else" do
    mare = @smiths.pets.create!(name: "Mare")
    LocationReport.create!(household: @smiths, subject: mare, location: @yard, reported_by: @member)
    wall
    assert_select ".wall-pet", text: /Mare/

    get edit_pet_path(mare)
    assert_select "input[type=checkbox][name='pet[on_wall]'][checked]"
    patch pet_path(mare), params: { pet: { on_wall: "0" } }
    assert_not mare.reload.on_wall?

    wall
    assert_select ".wall-pet", text: /Mare/, count: 0
    assert_select ".wall-place h2", text: "Yard", count: 0 # nobody else there
    get pets_path
    assert_select ".pet-card", text: /Mare/
  end

  test "the busiest place is on top; ties keep the household's place order; somewhere else is last" do
    LocationReport.create!(household: @smiths, subject: @member, location: @pool, reported_by: @member)
    LocationReport.create!(household: @smiths, subject: @admin, location: @house, reported_by: @admin)
    wall # one each: a house before a pool
    assert_equal [ "Big house", "Pool" ], css_select(".wall-place h2").map(&:text)

    rex = @smiths.pets.create!(name: "Rex")
    LocationReport.create!(household: @smiths, subject: rex, location: @pool, reported_by: @member)
    tom = @smiths.pets.create!(name: "Tom") # nowhere yet
    bo = @smiths.pets.create!(name: "Bo")
    LocationReport.create!(household: @smiths, subject: bo, location: @yard, reported_by: @member)
    assert_nil tom.status.report
    wall # pool 2, big house 1, yard 1, somewhere else 1 (Tom)
    assert_equal [ "Pool", "Big house", "Yard", "Somewhere else" ], css_select(".wall-place h2").map(&:text)
  end
end
