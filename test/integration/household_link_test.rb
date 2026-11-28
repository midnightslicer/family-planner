require "test_helper"

class HouseholdLinkTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @smiths = households(:smiths)
    @lake = Household.create!(name: "Lake House")
    HouseholdMembership.create!(user: @member, household: @lake)
    @strangers = Household.create!(name: "Strangers")
    sign_in @member
  end

  def current_household_name
    get account_root_path
    css_select(".household-switch option[selected]").first&.text
  end

  test "a notification link switches to its household and drops the param" do
    assert_equal "The Smiths", current_household_name # starts on the first one

    get tasks_path(person: @member.id, household: @lake.id)
    assert_redirected_to tasks_path(person: @member.id)
    assert_equal "Lake House", current_household_name
  end

  test "someone else's household id is ignored" do
    get tasks_path(household: @strangers.id)
    assert_redirected_to tasks_path
    assert_equal "The Smiths", current_household_name
  end

  test "signed out, the link survives sign-in" do
    sign_out @member
    get tasks_path(household: @lake.id)
    assert_redirected_to new_user_session_path
    post user_session_path, params: { user: { email: @member.email, password: "password" } }
    assert_redirected_to tasks_path(household: @lake.id)
    follow_redirect!
    assert_redirected_to tasks_path
    assert_equal "Lake House", current_household_name
  end

  test "being sent to sign in shows no \"you need to sign in\" toast" do
    sign_out @member
    get tasks_path
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_response :success
    assert_select "#flash .toast", count: 0
  end

  test "a doubled slash can't turn the redirect into another site" do
    get "//tasks?household=#{@lake.id}"
    assert_equal "/tasks", response.location.delete_prefix("http://www.example.com")
  end

  test "forms that send a household hash aren't affected" do
    sign_in users(:admin)
    patch admin_household_path(@smiths), params: { household: { name: "The Smiths" } }
    assert_response :redirect
  end
end
