require "test_helper"

class AdminNotificationsTest < ActionDispatch::IntegrationTest
  test "admins see whether push and email work, and the last failure" do
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    users(:member).push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/x",
                                              p256dh: WebPush::Base64Url.encode(browser.public_key.to_octet_string(:uncompressed)),
                                              auth: WebPush::Base64Url.encode(SecureRandom.random_bytes(16)),
                                              user_agent: "iPhone Safari/605", failed_at: 1.hour.ago, last_error: "403 Forbidden")
    sign_in users(:admin)
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
    sign_in users(:admin)
    [admin_settings_path, account_root_path, account_notifications_path].each do |path|
      get path
      assert_select "[id=notifications]", 1, path
      assert_select "#notifications.toast-stack", 1
    end
  end

  test "members can't see it" do
    sign_in users(:member)
    get admin_settings_path
    assert_response :forbidden
  end

  test "invitations explain how to get the app on a phone" do
    invitation = Invitation.create!(email: "sam@example.com", household: households(:smiths), invited_by: users(:admin))
    mail = InvitationMailer.invite(invitation, "https://status.example.com/invitations/abc")
    assert_includes mail.text_part.body.to_s, "Add to Home Screen"
    assert_includes mail.html_part.body.to_s, "Install app"
  end
end
