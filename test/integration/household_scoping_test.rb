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
    assert_select ".sched-title", text: "Other household task", count: 0
  end

  test "a task in another household is invisible (404) even by direct id" do
    get task_path(@other_task)
    assert_response :not_found
    assert_select "h1", "Nothing here" # the 404 page, not an empty body
    assert_select "a[href='/']", "Back home"
  end

  test "status actions on another household's task 404, with an empty body for Turbo" do
    # What Turbo sends for a form or button_to.
    post start_task_path(@other_task), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
    assert_response :not_found
    assert_empty response.body
    assert @other_task.reload.planned?
  end

  test "the dashboard lives at / only, with cards for this household's members" do
    get "/"
    assert_select ".person-card", 2 # admin + member, not other households' people
    assert_select "h1.visually-hidden", @smiths.name
    assert_select "a", text: "Add to my day", count: 0
    get "/dashboard"
    assert_response :not_found
  end

  test "dashboard spells out each person's status in words" do
    Task.create!(household: @smiths, title: "Dishes", assigned_to: @member, status: :in_progress)
    get root_path
    assert_select ".person-now", text: "Dishes"
    assert_select ".status-chip", text: "Text only"
    assert_select ".status-chip", text: "Free to call"
  end
end
