require "test_helper"

class AdminManagesProfilesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @smiths = households(:smiths)
    @house = @smiths.locations.create!(name: "Red Brick House", kind: "house")
  end

  test "an admin can change someone's profile and house" do
    sign_in @admin
    get tasks_path(person: @member.id)
    assert_select "a[href='#{edit_person_profile_path(@member)}']", text: "Manage profile"

    get edit_person_profile_path(@member)
    assert_response :success
    assert_select ".managing-banner", text: /managing Member User's details/
    assert_select "input[name='user[current_password]']", count: 0

    patch person_profile_path(@member), params: { user: { display_name: "Mom", color: "#ec4899", custom_color: "",
                                                          birthday: "1960-03-02", avatar: fixture_file_upload("avatar.png", "image/png") },
                                                  home_id: @house.id }
    assert_redirected_to edit_person_profile_path(@member)
    @member.reload
    assert_equal ["Mom", Date.new(1960, 3, 2)], [@member.display_name, @member.birthday]
    assert @member.avatar_saved?
    assert_equal @house, @member.home_in(@smiths)
  end

  test "an admin can set someone's work schedule and days off" do
    sign_in @admin
    get edit_work_schedule_path(person_id: @member.id)
    assert_select "h1", text: "Member's work schedule"

    patch work_schedule_path, params: { person_id: @member.id,
                                        work_schedule: { availability: "busy", days: { "1" => { on: "1", from_time: "08:00", until_time: "16:00", place: "Remote" } } } }
    assert_redirected_to edit_work_schedule_path(person_id: @member.id)
    assert_equal [1], @member.work_shifts.pluck(:weekday)
    assert_equal "busy", @member.reload.work_availability
    assert_empty @admin.work_shifts

    post days_off_path, params: { person_id: @member.id, day_off: { starts_on: Date.current + 1, note: "Doctor" } }
    off = @member.days_off.sole
    delete day_off_path(off, person_id: @member.id)
    assert_empty @member.days_off.reload
  end

  test "members can't manage anyone else" do
    sign_in @member
    get edit_person_profile_path(@admin)
    assert_response :not_found
    patch work_schedule_path, params: { person_id: @admin.id, work_schedule: { days: { "1" => { on: "1", from_time: "08:00", until_time: "16:00" } } } }
    assert_response :not_found
    assert_empty @admin.work_shifts
    post days_off_path, params: { person_id: @admin.id, day_off: { starts_on: Date.current } }
    assert_response :not_found
    get tasks_path(person: @admin.id)
    assert_select "a", text: "Manage profile", count: 0
  end

  test "admins can't reach people outside their household" do
    outsider = User.create!(email: "out@example.com", display_name: "Out", password: "long enough pw")
    Household.create!(name: "Others").users << outsider
    sign_in @admin
    get edit_person_profile_path(outsider)
    assert_response :not_found
  end

  test "an apostrophe in the page title is escaped once" do
    sign_in @admin
    get edit_person_profile_path(@member)
    assert_select "title", text: /\AMember User's profile/
  end

  test "your own profile stays on the account page" do
    sign_in @admin
    get edit_person_profile_path(@admin)
    assert_redirected_to account_root_path
  end
end
