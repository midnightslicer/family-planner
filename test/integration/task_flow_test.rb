require "test_helper"

class TaskFlowTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @smiths = households(:smiths)
    sign_in @member
  end

  test "new task form leaves the schedule collapsed and empty" do
    get new_task_path
    assert_response :success
    assert_select "details.form-field:not([open])"
    assert_select "input[name='task[starts_at]']:not([value])"
  end

  test "I'm doing this now creates the task already in progress" do
    post tasks_path, params: { start_now: "I'm doing this now", task: { title: "Dishes", assigned_to_id: @member.id } }

    task = Task.find_by!(title: "Dishes")
    assert task.in_progress?
    assert_not_nil task.starts_at
    assert_nil task.ends_at
  end

  test "save for later creates a planned task" do
    post tasks_path, params: { task: { title: "Laundry", assigned_to_id: @member.id } }
    assert Task.find_by!(title: "Laundry").planned?
  end

  test "tasks in progress are listed first" do
    Task.create!(household: @smiths, title: "Older, doing", status: :in_progress)
    Task.create!(household: @smiths, title: "Newer, planned")

    get tasks_path
    assert_select ".task-title" do |titles|
      assert_equal "Older, doing", titles.first.text
    end
  end

  test "task cards use plain wording" do
    Task.create!(household: @smiths, title: "Dishes", status: :in_progress)

    get tasks_path
    assert_select ".status-chip", text: "Doing"
    assert_select "button", text: "Done"
    assert_select "button", text: "Never mind"
  end
end
