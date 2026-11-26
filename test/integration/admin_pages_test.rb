require "test_helper"

# The admin screens are plain index/edit pages with no model logic of their
# own, so they regress silently. These assert they render at all (the
# invitations index once raised on a missing created_at column), plus the
# push-and-email status on Settings.
class AdminPagesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @household = households(:smiths)
    sign_in @admin
  end

  test "invitations are listed newest first, with their status" do
    old = Invitation.create!(email: "old@example.com", household: @household, invited_by: @admin)
    old.update_column(:created_at, 2.days.ago)
    recent = Invitation.create!(email: "recent@example.com", household: @household, invited_by: @admin)

    get admin_invitations_path
    assert_response :success
    assert_equal [ recent.email, old.email ],
                 css_select("tbody tr td:first-child").map { |td| td.text.strip }
    assert_select ".status-chip", text: "pending", count: 2
  end

  test "households, settings, people and account pages render" do
    [ admin_households_path, edit_admin_household_path(@household), admin_settings_path,
      admin_users_path, new_admin_invitation_path, account_root_path ].each do |path|
      get path
      assert_response :success, "#{path} returned #{response.status}"
    end
  end

  test "admins see whether push and email work, and the last failure" do
    users(:member).push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/x", **push_keys,
                                              user_agent: "iPhone Safari/605", failed_at: 1.hour.ago, last_error: "403 Forbidden")
    get admin_settings_path
    assert_response :success
    assert_select "#push-and-email + .admin-notifications" do
      assert_select "code", text: PushKeys.public_key
      assert_select "dd", text: /1 device across all households/
      assert_select "dd", text: /Member User's iPhone · Safari/
      assert_select "dd", text: /Email.*|Not set up/
    end
  end

  test "pages with a Notifications heading keep #notifications for the toasts" do
    [ admin_settings_path, account_root_path, account_notifications_path ].each do |path|
      get path
      assert_select "[id=notifications]", 1, path
      assert_select "#notifications.toast-stack", 1
    end
  end

  test "invitations explain how to get the app on a phone" do
    invitation = Invitation.create!(email: "sam@example.com", household: @household, invited_by: @admin)
    mail = InvitationMailer.invite(invitation, "https://status.example.com/invitations/abc")
    assert_includes mail.text_part.body.to_s, "Add to Home Screen"
    assert_includes mail.html_part.body.to_s, "Install app"
  end
end
