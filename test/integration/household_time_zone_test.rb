require "test_helper"

class HouseholdTimeZoneTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @smiths = households(:smiths)
  end

  def card(user) = "##{ActionView::RecordIdentifier.dom_id(user, :person_card)}"

  test "an admin sets the household's time zone" do
    sign_in @admin
    cookies[:tz] = "America/Chicago"
    get edit_admin_household_path(@smiths)
    assert_select "select[name='household[time_zone]'] option[selected]", text: /Central Time/

    patch admin_household_path(@smiths), params: { household: { name: @smiths.name, time_zone: "Central Time (US & Canada)" } }
    assert_equal "Central Time (US & Canada)", @smiths.reload.time_zone
  end

  test "an unknown zone is refused" do
    sign_in @admin
    patch admin_household_path(@smiths), params: { household: { name: @smiths.name, time_zone: "Mars/Olympus" } }
    assert_response :unprocessable_content
    assert_nil @smiths.reload.time_zone
  end

  test "members can't change it" do
    sign_in @member
    patch admin_household_path(@smiths), params: { household: { name: @smiths.name, time_zone: "Hawaii" } }
    assert_response :forbidden
  end

  test "once set, work hours and times follow the household's clock, not the phone's" do
    @smiths.update!(time_zone: "Central Time (US & Canada)")
    @member.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00", place: "Office")
    # Monday 10:00 in Chicago is 16:00 UTC and 08:00 in Los Angeles.
    travel_to Time.utc(2026, 11, 23, 16, 0) do
      sign_in @admin
      cookies[:tz] = "America/Los_Angeles"
      get root_path
      assert_select "#{card(@member)} .person-now", text: "Work · until 5 PM · Office"
    end
  end

  test "until it's set, each phone's own zone is used" do
    @member.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00", place: "Office")
    travel_to Time.utc(2026, 11, 23, 16, 0) do
      sign_in @admin
      cookies[:tz] = "America/Los_Angeles" # 08:00 there: not at work yet
      get root_path
      assert_select "#{card(@member)} .person-next", text: "Next: Work · 9 AM"
    end
  end

  test "the wall runs on the household's clock" do
    @smiths.update!(time_zone: "Central Time (US & Canada)")
    @member.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00", place: "Office")
    sign_in @member
    travel_to Time.utc(2026, 11, 23, 16, 0) do
      get wall_path(@smiths.slug)
      assert_select "#{card(@member)} .person-now", text: "Work · until 5 PM · Office"
    end
  end
end
