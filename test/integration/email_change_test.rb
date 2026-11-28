require "test_helper"

class EmailChangeTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    sign_in @member
  end

  test "change your email with your password" do
    get account_root_path
    assert_select "form[action='#{account_email_path}'] input[name='user[email]'][value='member@example.com']"

    patch account_email_path, params: { user: { email: "new@example.com", current_password: "wrong" } }
    assert_response :unprocessable_content
    assert_select ".flash-alert", text: /Current password is incorrect/
    assert_equal "member@example.com", @member.reload.email

    patch account_email_path, params: { user: { email: "new@example.com", current_password: "password" } }
    assert_redirected_to account_root_path
    assert_equal "new@example.com", @member.reload.email

    sign_out @member
    post user_session_path, params: { user: { email: "new@example.com", password: "password" } }
    assert_redirected_to root_path
  end

  test "an email someone else has is refused" do
    patch account_email_path, params: { user: { email: users(:admin).email, current_password: "password" } }
    assert_response :unprocessable_content
    assert_equal "member@example.com", @member.reload.email
  end

  test "the old address hears about it when email is set up" do
    Setting.set("smtp_host", "smtp.example.com")
    assert_enqueued_emails 1 do
      patch account_email_path, params: { user: { email: "new@example.com", current_password: "password" } }
    end
  ensure
    Setting.set("smtp_host", nil)
  end

  test "sign-up says the email can be changed later" do
    sign_out @member
    invitation = Invitation.create!(household: households(:smiths), invited_by: users(:admin), email: "kid@example.com")
    get invitation_path(invitation.raw_token)
    assert_select "small", text: /change it on your account page/
  end
end
