require "test_helper"

class TaskRecurrenceTest < ActiveSupport::TestCase
  setup do
    @household = households(:smiths)
    @admin = users(:admin)
    @member = users(:member)
  end

  test "completing a recurring task creates a new planned copy with next start" do
    base = Time.zone.local(2026, 9, 23, 9, 0, 0)
    task = Task.create!(
      household: @household, title: "Standup", assigned_to: @member, created_by: @admin,
      starts_at: base, ends_at: base + 30.minutes, recurrence_interval: "daily"
    )

    task.start!
    assert task.in_progress?

    task.complete!
    assert task.completed?
    assert_nil task.next_occurrence

    copy = Task.where(title: "Standup").where.not(id: task.id).sole
    assert copy.planned?
    assert_equal "daily", copy.recurrence_interval
    assert_equal base + 1.day, copy.starts_at
    assert_equal @member, copy.assigned_to
    assert_equal @household, copy.household
  end

  test "weekly recurrence advances seven days and biweekly fourteen" do
    base = Time.zone.local(2026, 9, 23, 9, 0, 0)

    weekly = Task.create!(household: @household, title: "Weekly", recurrence_interval: "weekly", starts_at: base)
    weekly.start!
    weekly.complete!
    assert_equal base + 7.days, Task.where(title: "Weekly").order(:id).last.starts_at

    biweekly = Task.create!(household: @household, title: "Biweekly", recurrence_interval: "biweekly", starts_at: base)
    biweekly.start!
    biweekly.complete!
    assert_equal base + 14.days, Task.where(title: "Biweekly").order(:id).last.starts_at
  end

  test "monthly recurrence clamps day to target month length" do
    # Jan 31 → Feb 28 (2026 is not a leap year)
    base = Time.zone.local(2026, 1, 31, 9, 0, 0)
    task = Task.create!(household: @household, title: "Monthly", recurrence_interval: "monthly", starts_at: base)
    task.start!
    task.cancel!

    copy = Task.where(title: "Monthly").where.not(id: task.id).sole
    assert_equal Time.zone.local(2026, 2, 28, 9, 0, 0), copy.starts_at
    assert copy.planned?
  end

  test "non-recurring tasks do not spawn copies" do
    task = Task.create!(household: @household, title: "One-off", recurrence_interval: "")
    task.start!
    task.complete!
    assert_equal 1, Task.where(title: "One-off").count
  end

  test "start sets starts_at to now when nil" do
    freeze_time = Time.zone.local(2026, 9, 23, 12, 0, 0)
    travel_to freeze_time do
      task = Task.create!(household: @household, title: "No start time")
      task.start!
      assert task.in_progress?
      assert_equal freeze_time, task.starts_at
    end
  end

  test "assignee must belong to the task's household" do
    outsider = User.create!(email: "outsider@example.com", handle: "outsider",
                            display_name: "Outsider", password: "secret123")
    task = Task.new(household: @household, title: "Bad assignee", assigned_to: outsider)
    assert_not task.valid?
    assert_equal ["must be a member of the task's household"], task.errors[:assigned_to_id]
  end

  test "status transitions only move along allowed paths" do
    task = Task.create!(household: @household, title: "Flow")

    assert_not task.complete!          # planned → completed forbidden
    assert task.planned?

    assert task.start!
    assert task.in_progress?

    assert task.cancel!
    assert task.undone?
    assert_not task.complete!          # undone → completed forbidden
    assert_not task.start!             # undone → in_progress forbidden
  end
end