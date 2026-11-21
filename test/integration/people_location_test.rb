require "test_helper"

class PeopleLocationTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    @yard = @smiths.locations.create!(name: "Yard", kind: "yard")
    sign_in @member
  end

  test "you can report your own location from your profile" do
    get person_path(@member)
    assert_select "input[name='location_report[location_id]'][value='#{@yard.id}']"

    post locate_me_path, params: { location_report: { location_id: @yard.id, comment: "Mowing" } }
    assert_redirected_to person_path(@member)
    report = @member.location_reports.last
    assert_equal @yard, report.location
    assert_equal @member, report.reported_by

    get dashboard_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(@member, :person_card)} .person-where", text: /Yard/
  end

  test "someone else's profile has no form to set their location" do
    get person_path(@admin)
    assert_response :success
    assert_select "input[name='location_report[location_id]']", count: 0
  end

  test "the location endpoint can't be pointed at another person" do
    post locate_me_path, params: { location_report: { location_id: @yard.id, subject_id: @admin.id, subject_type: "User" } }
    assert_equal 0, @admin.location_reports.count
    assert_equal 1, @member.location_reports.count
  end

  test "a location from another household is refused" do
    theirs = Household.create!(name: "Others").locations.create!(name: "Theirs")
    post locate_me_path, params: { location_report: { location_id: theirs.id } }
    assert_response :unprocessable_content
    assert_equal 0, LocationReport.count
  end

  test "you can add a new place while setting your location" do
    post locate_me_path, params: { location_report: { location_id: "new", new_location_name: "Office" } }
    assert_redirected_to person_path(@member)
    assert_equal "Office", @member.location_reports.last.location.name
  end

  test "birthdays save on the account page and ages show on the profile" do
    patch account_profile_path, params: { user: { display_name: @member.display_name, handle: @member.handle,
                                                  color: @member.color, custom_color: "", birthday: "1990-05-04" } }
    assert_equal Date.new(1990, 5, 4), @member.reload.birthday
    get person_path(@member)
    assert_select ".profile-heading", text: /years · born May 4, 1990/
  end
end
