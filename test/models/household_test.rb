require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
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
end
