require "test_helper"
require "turbo/broadcastable/test_helper"

# Only whoever a to-do is for can tick it off (or start, skip or bring it
# back). Whoever added it for them can edit or delete it, not do it.
class TodoOwnershipTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper
  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
  end

  test "someone else's to-do can't be ticked off, started or skipped" do
    task = Task.create!(household: @smiths, title: "Sweep", assigned_to: @admin, created_by: @admin)
    sign_in @member
    get tasks_path(person: @admin.id)
    assert_select "##{dom_id(task)} button.sched-check", count: 0
    assert_select "##{dom_id(task)} .sched-check.is-locked"
    assert_select "##{dom_id(task)} form[action='#{start_task_path(task)}']", count: 0
    assert_select "##{dom_id(task)} form[action='#{cancel_task_path(task)}']", count: 0

    [ complete_task_path(task), start_task_path(task), cancel_task_path(task) ].each do |path|
      post path, headers: { "Referer" => tasks_url(person: @admin.id) }
      assert_redirected_to tasks_url(person: @admin.id)
    end
    assert task.reload.planned?
    follow_redirect!
    assert_select ".flash-alert", text: /Only the person it's for/
  end

  test "adding a to-do for someone lets you edit or delete it, not mark it done" do
    sign_in @member
    post tasks_path, params: { task: { title: "Take out the trash", assignee_ids: [ @admin.id ] } }
    task = Task.find_by!(title: "Take out the trash")
    get tasks_path(person: @admin.id)
    assert_select "##{dom_id(task)} a[href='#{edit_task_path(task)}']"
    assert_select "##{dom_id(task)} form[action='#{task_path(task)}'] input[name=_method][value=delete]"
    assert_select "##{dom_id(task)} button.sched-check", count: 0

    post complete_task_path(task)
    assert task.reload.planned?
    patch task_path(task), params: { task: { title: "Take out the recycling", assignee_ids: [ @admin.id ] } }
    assert_equal "Take out the recycling", task.reload.title
    delete task_path(task)
    assert_not Task.exists?(task.id)
  end

  test "a to-do for anyone is anyone's to do" do
    task = Task.create!(household: @smiths, title: "Water the plants", created_by: @admin)
    sign_in @member
    post complete_task_path(task)
    assert task.reload.completed?
  end

  test "ticked off by mistake? bring it back" do
    task = Task.create!(household: @smiths, title: "Pay the bill", assigned_to: @member, created_by: @member)
    sign_in @member
    post complete_task_path(task)
    get tasks_path
    assert_select ".done-today ##{dom_id(task)} form[action='#{reopen_task_path(task)}']"

    post reopen_task_path(task), headers: { "Referer" => tasks_url }
    follow_redirect!
    assert_select ".flash-notice", text: "Pay the bill is back on the list."
    task.reload
    assert task.planned?
    assert_nil task.finished_at
    assert_nil task.finished_by
    assert_select "##{dom_id(task)} button.sched-check"

    # Only its owner can bring it back.
    post complete_task_path(task)
    sign_in @admin
    post reopen_task_path(task)
    assert task.reload.completed?
  end

  test "bringing back a repeating to-do takes back the copy it made" do
    task = Task.create!(household: @smiths, title: "Feed the fish", assigned_to: @member, created_by: @member,
                        recurrence_interval: "daily")
    sign_in @member
    post complete_task_path(task)
    copy = task.reload.next_task
    assert copy.planned?

    assert_difference -> { Task.count }, -1 do
      post reopen_task_path(task)
    end
    assert task.reload.planned?
    assert_not Task.exists?(copy.id)
  end

  test "a repeating to-do whose next copy is underway stays done" do
    task = Task.create!(household: @smiths, title: "Walk", assigned_to: @member, created_by: @member, recurrence_interval: "daily")
    sign_in @member
    post complete_task_path(task)
    task.reload.next_task.start!
    assert_not task.reload.reopenable?
    post reopen_task_path(task)
    assert task.reload.completed?
  end

  test "whoever else it's for hears that it's back" do
    task = Task.create!(household: @smiths, title: "Shop", created_by: @admin)
    task.assignments.create!(user: @member, status: "accepted")
    task.assignments.create!(user: @admin, status: "accepted")
    sign_in @member
    post complete_task_path(task)
    post reopen_task_path(task)
    assert_includes capture_turbo_stream_broadcasts([ @admin, :notifications ]).last.to_html, "Member User brought back Shop"
  end
end
