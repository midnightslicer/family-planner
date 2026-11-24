require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  test "a new household gets a readable, unique wall slug from its name" do
    first = Household.create!(name: "Grandma's House!")
    assert_equal "grandma-s-house", first.slug
    assert_equal "grandma-s-house-2", Household.create!(name: "Grandma's house").slug
    assert_equal "home", Household.create!(name: "!!!").slug
  end

  test "a slug can be edited but must be a plain address and unique" do
    household = households(:smiths)
    assert household.update(slug: "Our Place")
    assert_equal "our-place", household.slug

    other = Household.create!(name: "Others")
    assert_not other.update(slug: "our-place")
    assert_not other.update(slug: "")
  end

  test "member_statuses finds each member's current and next task in a fixed number of queries" do
    household = households(:smiths)
    member = users(:member)
    Task.create!(household: household, title: "Later", assigned_to: member, starts_at: 2.hours.from_now)
    Task.create!(household: household, title: "Sooner", assigned_to: member, starts_at: 1.hour.from_now)
    Task.create!(household: household, title: "Now", assigned_to: member, status: :in_progress)
    Task.create!(household: household, title: "Done", assigned_to: member, status: :completed)

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    statuses = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { household.member_statuses }

    assert_operator queries, :<=, 7 # tasks, locations, members with work hours and days off, last whereabouts: never one per member
    assert_equal "Now", statuses[member.id][:current].title
    assert_equal "Sooner", statuses[member.id][:next].title
    assert_equal({}, statuses[users(:admin).id])
  end

  test "member_statuses includes where each member last said they were" do
    household = households(:smiths)
    member = users(:member)
    yard = household.locations.create!(name: "Yard", kind: "yard")
    house = household.locations.create!(name: "House", kind: "house")
    LocationReport.create!(household: household, subject: member, location: yard, reported_by: member)
    LocationReport.create!(household: household, subject: member, location: house, reported_by: member, comment: "Inside")

    status = household.member_statuses[member.id]
    assert_equal "House", status[:location].location.name
    assert_equal "Inside", status[:location].comment
  end

  test "tasks can't end before they start" do
    task = Task.new(household: households(:smiths), title: "Oops", starts_at: Time.current, ends_at: 1.hour.ago)
    assert_not task.valid?
    assert task.errors.include?(:ends_at)
  end

  test "a shared event is on every card it's for, and the batched loaders agree" do
    smiths = households(:smiths)
    admin, member = users(:admin), users(:member)
    yard = smiths.locations.create!(name: "Yard", kind: "yard")
    travel_to Time.zone.local(2026, 11, 24, 10, 0) do
      picnic = Task.create!(household: smiths, title: "Picnic", assigned_to: admin, place: "Yard",
                            starts_at: 10.minutes.ago, ends_at: 1.hour.from_now)
      picnic.assignments.create!(user: member, status: "accepted")
      Task.create!(household: smiths, title: "Lunch", assigned_to: member, starts_at: 2.hours.from_now)

      [smiths.member_statuses, smiths.member_statuses(members: smiths.board_members, places: smiths.places)].each do |statuses|
        assert_equal ["Picnic", "Picnic"], [statuses[admin.id][:current].title, statuses[member.id][:current].title]
        assert_equal [yard, yard], [statuses[admin.id][:at], statuses[member.id][:at]]
        assert_equal "Lunch", statuses[member.id][:next].title
        assert_nil statuses[admin.id][:next]
      end
    end
  end
end
