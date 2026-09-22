require "test_helper"

class HouseholdScopingTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @smiths = households(:smiths)
    # A second household the member does NOT belong to.
    @other = Household.create!(name: "Other House")
    @other_task = Task.create!(household: @other, title: "Other household task")
    sign_in @member
  end

  test "tasks index only shows current household tasks" do
    get tasks_path
    assert_response :success
    assert_select ".task-title", text: "Other household task", count: 0
  end

  test "a task in another household is invisible (404) even by direct id" do
    get task_path(@other_task)
    assert_response :not_found
  end

  test "status actions on another household's task 404" do
    post start_task_path(@other_task)
    assert_response :not_found
    assert @other_task.reload.planned?
  end

  test "dashboard only renders cards for current household members" do
    get dashboard_path
    assert_response :success
    assert_select ".person-card", count: 2  # admin + member, not other-household users
  end
end