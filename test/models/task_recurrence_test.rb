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

  test "weekly, biweekly and monthly intervals; skipping rolls on too, and a month end clamps" do
    base = Time.zone.local(2026, 1, 31, 9, 0, 0)
    { "weekly" => base + 7.days, "biweekly" => base + 14.days,
      "monthly" => Time.zone.local(2026, 2, 28, 9, 0, 0) }.each do |interval, expected|
      task = Task.create!(household: @household, title: interval, recurrence_interval: interval, starts_at: base)
      task.cancel!
      copy = Task.where(title: interval).where.not(id: task.id).sole
      assert copy.planned?
      assert_equal expected, copy.starts_at, interval
    end
  end

  # "" reads back as the enum key "no_recurrence", which is .present?.
  test "non-recurring tasks do not spawn copies" do
    task = Task.create!(household: @household, title: "One-off", recurrence_interval: "")
    task.start!
    task.complete!
    assert_equal 1, Task.where(title: "One-off").count
  end

  test "start records when it was started, leaving the scheduled time alone" do
    freeze_time = Time.zone.local(2026, 9, 23, 12, 0, 0)
    travel_to freeze_time do
      task = Task.create!(household: @household, title: "No start time")
      task.start!
      assert task.in_progress?
      assert_equal freeze_time, task.started_at
      assert_nil task.starts_at
      assert_not task.timed?
    end
  end

  test "a recurring to-do comes back on its next day, still without a time" do
    travel_to Time.zone.local(2026, 11, 22, 9, 0) do
      task = Task.create!(household: @household, title: "Vitamins", recurrence_interval: "daily")
      task.complete!
      copy = Task.where(title: "Vitamins").planned.sole
      assert_nil copy.starts_at
      assert_equal Date.new(2026, 11, 23), copy.due_on
    end
  end

  test "assignee must belong to the task's household" do
    outsider = User.create!(email: "outsider@example.com",
                            display_name: "Outsider", password: "secret123")
    task = Task.new(household: @household, title: "Bad assignee", assigned_to: outsider)
    assert_not task.valid?
    assert_equal [ "must be in the household" ], task.assignments.first.errors[:user]
  end

  test "status transitions only move along allowed paths" do
    task = Task.create!(household: @household, title: "Flow")

    assert task.start!
    assert task.in_progress?

    assert task.cancel!
    assert task.undone?
    assert_not task.complete!          # undone → completed forbidden
    assert task.start!                 # cancelled one-off can be restarted
    assert task.in_progress?
  end

  test "a cancelled recurring task cannot be restarted" do
    task = Task.create!(household: @household, title: "Chores", recurrence_interval: "weekly")
    task.start!
    task.cancel!

    assert_not task.restartable?
    assert_not task.start!             # its next copy already exists
    assert task.undone?
  end

  test "pause returns an in-progress task to planned so it can be resumed" do
    task = Task.create!(household: @household, title: "Homework", recurrence_interval: "daily")
    assert_not task.pause!             # planned → planned forbidden

    task.start!
    started_at = task.started_at
    assert_no_difference -> { Task.count } do   # pausing never spawns a recurrence
      assert task.pause!
    end
    assert task.planned?

    assert task.start!
    assert task.in_progress?
    assert_operator task.started_at, :>=, started_at
  end

  test "finishing or skipping, even straight from planned, stamps when; restarting clears it" do
    travel_to Time.zone.local(2026, 11, 22, 9, 0) do
      task = Task.create!(household: @household, title: "Stamp")
      assert task.complete!
      assert_equal Time.current, task.finished_at

      one_off = Task.create!(household: @household, title: "Skip me")
      assert one_off.cancel!
      assert one_off.undone?
      assert_equal Time.current, one_off.finished_at
      one_off.start!
      assert_nil one_off.finished_at
    end
  end

  test "a repeating event that rolls on is stamped finished when it ended" do
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      past = Task.create!(household: @household, title: "Church", recurrence_interval: "weekly",
                          starts_at: Time.zone.local(2026, 11, 22, 10, 0), ends_at: Time.zone.local(2026, 11, 22, 11, 0))
      past.roll_forward!
      assert_equal Time.zone.local(2026, 11, 22, 11, 0), past.reload.finished_at
    end
  end
end
