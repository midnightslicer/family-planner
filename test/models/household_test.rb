require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  test "member_statuses finds each member's current and next task in one query" do
    household = households(:smiths)
    member = users(:member)
    Task.create!(household: household, title: "Later", assigned_to: member, starts_at: 2.hours.from_now)
    Task.create!(household: household, title: "Sooner", assigned_to: member, starts_at: 1.hour.from_now)
    Task.create!(household: household, title: "Now", assigned_to: member, status: :in_progress)
    Task.create!(household: household, title: "Done", assigned_to: member, status: :completed)

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    statuses = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { household.member_statuses }

    assert_equal 1, queries
    assert_equal "Now", statuses[member.id][:current].title
    assert_equal "Sooner", statuses[member.id][:next].title
    assert_equal({}, statuses[users(:admin).id])
  end

  test "tasks can't end before they start" do
    task = Task.new(household: households(:smiths), title: "Oops", starts_at: Time.current, ends_at: 1.hour.ago)
    assert_not task.valid?
    assert task.errors.include?(:ends_at)
  end
end
