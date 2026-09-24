require "test_helper"

# Regression tests for the security review: each one pins a hole that was
# open before.
class SecurityTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @household = households(:smiths)
  end

  test "task titles are escaped in turbo stream flash messages" do
    sign_in @member
    task = Task.create!(household: @household, title: "<img src=x onerror=alert(1)>", created_by: @member)
    post start_task_path(task), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_no_match(/<img src=x/, response.body)
    assert_match(/&lt;img src=x/, response.body)
  end

  test "the saved SMTP password is never sent back to the browser" do
    Setting.set("smtp_password", "hunter2-secret")
    sign_in @admin
    get admin_settings_path
    assert_response :success
    assert_no_match(/hunter2-secret/, response.body)

    patch admin_settings_path, params: { settings: { smtp_host: "smtp.example.com", smtp_password: "" } }
    assert_equal "hunter2-secret", Setting.get("smtp_password"), "blank keeps the saved password"
    patch admin_settings_path, params: { settings: { clear_smtp_password: "1" } }
    assert_nil Setting.get("smtp_password")
  end

  test "SMTP TLS checkbox round-trips" do
    sign_in @admin
    patch admin_settings_path, params: { settings: { smtp_tls: "1" } }
    assert_equal "true", Setting.get("smtp_tls")
    patch admin_settings_path, params: { settings: { smtp_tls: "0" } }
    assert_nil Setting.get("smtp_tls")
  end

  test "invite links use the saved public address, not the Host header" do
    Setting.set("app_url", "https://status.example.org")
    sign_in @admin
    post admin_invitations_path, params: { invitation: { email: "", household_id: @household.id } },
                                 headers: { "Host" => "evil.example" }
    follow_redirect!
    assert_select "input#invite_link[value^=?]", "https://status.example.org/invitations/"
  end

  test "revoking an invitation works" do
    invitation = Invitation.create!(email: "x@example.com", household: @household, invited_by: @admin)
    sign_in @admin
    delete admin_invitation_path(invitation)
    assert_redirected_to admin_invitations_path
    assert_not Invitation.exists?(invitation.id)
  end

  test "switching household needs a signed-in member" do
    post switch_household_path, params: { household_id: @household.id }
    assert_redirected_to new_user_session_path
  end

  test "members can't reach the admin area" do
    sign_in @member
    get admin_users_path
    assert_response :forbidden
  end

  test "members can't edit tasks someone else created" do
    task = Task.create!(household: @household, title: "Admin's", created_by: @admin)
    sign_in @member
    patch task_path(task), params: { task: { title: "Mine now" } }
    assert_response :forbidden
    assert_equal "Admin's", task.reload.title
  end

  test "the wall needs the current token" do
    get wall_path("not-a-token")
    assert_response :not_found

    old_token = @household.dashboard_token
    sign_in @admin
    post regenerate_wall_link_admin_household_path(@household)
    sign_out @admin

    get wall_path(old_token)
    assert_response :not_found
    get wall_path(@household.reload.dashboard_token)
    assert_response :success
    assert_select ".person-card", 2
  end

  test "a member without a household sees a message, not a redirect loop" do
    @member.household_memberships.destroy_all
    sign_in @member
    get dashboard_path
    assert_response :success
    assert_select "h1", "You're not in a household yet"
  end

  test "pages carry a content security policy" do
    sign_in @member
    get dashboard_path
    policy = response.headers["Content-Security-Policy"]
    assert_match(/script-src 'self'/, policy)
    assert_match(/object-src 'none'/, policy)
  end

  test "there is no public sign-up route" do
    get "/users/sign_up"
    assert_response :not_found
  end
end
