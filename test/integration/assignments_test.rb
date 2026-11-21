require "test_helper"
require "turbo/broadcastable/test_helper"

class AssignmentsTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @me = users(:member)
    @mom = users(:admin)
    @smiths = households(:smiths)
    sign_in @me
  end

  def sunday_at(hour) = Time.zone.local(2026, 11, 29, hour)

  test "giving someone a to-do puts it on their list, not mine, and says so" do
    post tasks_path, params: { task: { title: "Call the chiropractor", assignee_ids: ["", @mom.id] } }
    task = Task.find_by!(title: "Call the chiropractor")
    assert_equal [@mom], task.people
    follow_redirect!
    assert_select ".flash-notice", text: "Added Call the chiropractor for Admin User."

    get tasks_path
    assert_select ".sched-title", text: "Call the chiropractor", count: 0
    get tasks_path(person: @mom.id)
    assert_select ".sched-title", text: "Call the chiropractor"
  end

  test "they're told about it" do
    assert_turbo_stream_broadcasts [@mom, :notifications], count: 1 do
      post tasks_path, params: { task: { title: "Call the chiropractor", assignee_ids: [@mom.id] } }
    end
  end

  test "an event for two goes on both schedules and both cards" do
    travel_to sunday_at(8) do
      sign_in @me
      post tasks_path, params: { task: { title: "Church", assignee_ids: [@me.id, @mom.id], on_date: "2026-11-29",
                                         from_time: "10:00", until_time: "11:30", availability: "busy" } }
      church = Task.find_by!(title: "Church")
      assert_equal [@me, @mom].sort_by(&:id), church.people.sort_by(&:id)
      follow_redirect!
      assert_select ".flash-notice", text: "Added Church for you and Admin User."
    end
    travel_to sunday_at(10) do
      reset! # two hours on, the old session has timed out
      sign_in @me
      get dashboard_path
      [@me, @mom].each do |person|
        assert_select "##{ActionView::RecordIdentifier.dom_id(person, :person_card)} .avail-busy", text: "Do not disturb"
      end
    end
  end

  test "a clash makes it wait for their OK, and the saver hears why" do
    Task.create!(household: @smiths, title: "Dentist", assigned_to: @mom, starts_at: sunday_at(10), ends_at: sunday_at(11))
    travel_to sunday_at(8) do
      sign_in @me
      post tasks_path, params: { task: { title: "Church", assignee_ids: [@me.id, @mom.id], on_date: "2026-11-29", from_time: "10:00" } }
      church = Task.find_by!(title: "Church")
      assert church.assignment_for(@mom).pending?
      assert church.assignment_for(@me).accepted?
      follow_redirect!
      assert_select ".flash-notice", text: "Added Church for you. Admin User has Dentist then, so it's waiting for Admin User's OK."

      # It isn't on her day yet; it waits for her.
      sign_in @mom
      get tasks_path
      assert_select ".waiting-panel .sched-title", text: "Church"
      assert_select ".waiting-panel .sched-conflict", text: /Clashes with Dentist/
      assert_select ".schedule-columns .sched-title", text: "Church", count: 0
    end
  end

  test "work hours count as a clash" do
    @mom.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00")
    monday = Time.zone.local(2026, 11, 30, 12)
    travel_to monday - 3.hours do
      sign_in @me
      post tasks_path, params: { task: { title: "Lunch", assignee_ids: [@mom.id], on_date: "2026-11-30", from_time: "12:00" } }
      assert Task.find_by!(title: "Lunch").assignment_for(@mom).pending?
    end
  end

  test "to-dos never clash" do
    Task.create!(household: @smiths, title: "Busy all day", assigned_to: @mom, starts_at: 1.hour.ago, ends_at: 10.hours.from_now)
    post tasks_path, params: { task: { title: "Buy milk", assignee_ids: [@mom.id] } }
    assert Task.find_by!(title: "Buy milk").assignment_for(@mom).accepted?
  end

  test "accepting and declining tell whoever added it" do
    task = Task.create!(household: @smiths, title: "Church", created_by: @me, starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour)
    task.assignments.create!(user: @mom, status: "pending", conflict_note: "Clashes with Dentist")
    sign_in @mom
    assert_turbo_stream_broadcasts [@me, :notifications], count: 1 do
      post accept_task_path(task)
    end
    assert task.assignment_for(@mom).reload.accepted?

    assert_turbo_stream_broadcasts [@me, :notifications], count: 1 do
      post decline_task_path(task)
    end
    assert task.assignment_for(@mom).reload.declined?
    assert task.reload.planned?, "declining doesn't cancel it for everyone"
    get tasks_path
    assert_select ".sched-title", text: "Church", count: 0
  end

  test "someone given a to-do can decline it, not skip it for everyone" do
    task = Task.create!(household: @smiths, title: "Call the chiropractor", created_by: @me, assigned_to: @mom)
    sign_in @mom
    get tasks_path
    assert_select "form[action='#{decline_task_path(task)}']"
    assert_select "form[action='#{cancel_task_path(task)}']", count: 0
  end

  test "follow up keeps it on my list and tells me when it's done" do
    post tasks_path, params: { task: { title: "Call the chiropractor", assignee_ids: [@mom.id], follow_up: "1" } }
    task = Task.find_by!(title: "Call the chiropractor")
    get tasks_path
    assert_select ".section-title", text: /Following up/
    assert_select ".sched-title", text: "Call the chiropractor"

    sign_in @mom
    assert_turbo_stream_broadcasts [@me, :notifications], count: 1 do
      post complete_task_path(task)
    end
  end

  test "whoever ticks off a shared item gets the credit" do
    task = Task.create!(household: @smiths, title: "Clean the garage", created_by: @me)
    task.assignments.create!(user: @me)
    task.assignments.create!(user: @mom)
    sign_in @mom
    post complete_task_path(task)
    assert_equal @mom, task.reload.finished_by
    assert_equal 1, @mom.finished_tasks.completed.count
    assert_equal 0, @me.finished_tasks.count
  end

  test "without follow up it's off my list" do
    post tasks_path, params: { task: { title: "Call the chiropractor", assignee_ids: [@mom.id] } }
    get tasks_path
    assert_select ".sched-title", text: "Call the chiropractor", count: 0
  end

  test "picking nobody makes it for anyone" do
    post tasks_path, params: { task: { title: "Take the trash out", assignee_ids: [""] } }
    assert_empty Task.find_by!(title: "Take the trash out").assignments
    get tasks_path(person: "family")
    assert_select ".sched-title", text: "Take the trash out"
  end

  test "taking someone off an item says so" do
    task = Task.create!(household: @smiths, title: "Church", created_by: @me, assigned_to: @mom)
    patch task_path(task), params: { task: { title: "Church", assignee_ids: ["", @me.id] } }
    follow_redirect!
    assert_select ".flash-notice", text: /Took it off Admin User's list/
    assert_equal [@me], task.reload.people
  end

  test "moving an event re-checks the others for clashes" do
    Task.create!(household: @smiths, title: "Dentist", assigned_to: @mom, starts_at: sunday_at(14), ends_at: sunday_at(15))
    travel_to sunday_at(8) do
      sign_in @me
      post tasks_path, params: { task: { title: "Picnic", assignee_ids: [@me.id, @mom.id], on_date: "2026-11-29", from_time: "12:00" } }
      picnic = Task.find_by!(title: "Picnic")
      assert picnic.assignment_for(@mom).accepted?

      patch task_path(picnic), params: { task: { title: "Picnic", assignee_ids: [@me.id, @mom.id], on_date: "2026-11-29", from_time: "14:00" } }
      assert picnic.assignment_for(@mom).reload.pending?
    end
  end

  test "a shared repeating event comes round for everyone on it" do
    travel_to sunday_at(12) do
      task = Task.create!(household: @smiths, title: "Church", recurrence_interval: "weekly",
                          starts_at: sunday_at(10) - 7.days, ends_at: sunday_at(11) - 7.days)
      task.assignments.create!(user: @me)
      task.assignments.create!(user: @mom)
      @smiths.roll_recurring_events!
      upcoming = Task.where(title: "Church").planned.sole
      assert_equal [@me.id, @mom.id].sort, upcoming.people.map(&:id).sort
    end
  end
end
