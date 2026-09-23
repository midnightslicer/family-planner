require "test_helper"

# The admin screens are plain index/edit pages with no model logic of their
# own, so they regress silently. These assert they render at all — the
# invitations index in particular raised on a missing created_at column and a
# missing Invitation#accepted?.
class AdminPagesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @household = households(:smiths)
    sign_in @admin
  end

  test "invitations index renders with a pending invitation" do
    Invitation.create!(email: "new@example.com", household: @household, invited_by: @admin)

    get admin_invitations_path
    assert_response :success
    assert_select ".table-wrap table tbody tr", 1
    assert_select ".status-chip", text: "pending"
  end

  test "invitations are listed newest first" do
    old = Invitation.create!(email: "old@example.com", household: @household, invited_by: @admin)
    old.update_column(:created_at, 2.days.ago)
    recent = Invitation.create!(email: "recent@example.com", household: @household, invited_by: @admin)

    get admin_invitations_path
    assert_response :success
    assert_equal [ recent.email, old.email ],
                 css_select("tbody tr td:first-child").map { |td| td.text.strip }
  end

  test "households, settings and profile render" do
    [ admin_households_path, admin_settings_path, admin_profile_path ].each do |path|
      get path
      assert_response :success, "#{path} returned #{response.status}"
    end
  end
end
