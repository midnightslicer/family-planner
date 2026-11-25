require "test_helper"

class PeopleLocationTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    @yard = @smiths.locations.create!(name: "Yard", kind: "yard")
    sign_in @member
  end

  test "your day has one-tap I'm at chips that set your location" do
    get tasks_path
    assert_select ".where-chips button", text: "Yard"

    post locate_me_path, params: { location_report: { location_id: @yard.id } }, headers: { "Referer" => tasks_url }
    assert_redirected_to tasks_url
    report = @member.location_reports.last
    assert_equal @yard, report.location
    assert_equal @member, report.reported_by

    get root_path
    assert_select "##{dom_id(@yard, :board_place)} #{card(@member)}"
    assert_select "#{card(@member)} .person-where", count: 0
    get tasks_path
    assert_select ".day-where", text: /Yard/
    assert_select ".where-chip.is-current", text: "Yard"
  end

  test "the Off property chip reports you with no location" do
    get tasks_path
    assert_select ".where-chips button", text: "Off property"

    post locate_me_path, params: { location_report: { off_property: "1" } }, headers: { "Referer" => tasks_url }
    assert_nil @member.location_reports.last.location
    get tasks_path
    assert_select ".day-where", text: /Off property/
    assert_select ".where-chip.is-current", text: "Off property"
    get root_path
    assert_select ".person-where", text: /Off property/
  end

  test "someone else's day shows where they are but no way to set it or their status" do
    LocationReport.create!(household: @smiths, subject: @admin, location: @yard, reported_by: @admin)
    get tasks_path(person: @admin.id)
    assert_select ".day-where", text: /Yard/
    assert_select ".where-bar", count: 0
    assert_select ".status-bar", count: 0
  end

  test "the old profile address leads to their day" do
    get person_path(@admin)
    assert_redirected_to tasks_path(person: @admin.id)
  end

  test "the location endpoint can't be pointed at another person" do
    post locate_me_path, params: { location_report: { location_id: @yard.id, subject_id: @admin.id, subject_type: "User" } }
    assert_equal 0, @admin.location_reports.count
    assert_equal 1, @member.location_reports.count
  end

  test "a location from another household is refused" do
    theirs = Household.create!(name: "Others").locations.create!(name: "Theirs")
    post locate_me_path, params: { location_report: { location_id: theirs.id } }
    follow_redirect!
    assert_select ".flash-alert"
    assert_equal 0, LocationReport.count
  end

  test "you can add a new place with a note while setting your location" do
    post locate_me_path, params: { location_report: { location_id: "new", new_location_name: "Office", comment: "Back by 6" } }
    report = @member.location_reports.last
    assert_equal "Office", report.location.name
    assert_equal "Back by 6", report.comment
  end

  test "birthdays save on the account page and ages show on your day" do
    patch account_profile_path, params: { user: { display_name: @member.display_name,
                                                  color: @member.color, custom_color: "", birthday: "1990-05-04" } }
    assert_equal Date.new(1990, 5, 4), @member.reload.birthday
    get tasks_path
    assert_select ".profile-heading", text: /years/
  end
end
