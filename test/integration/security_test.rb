require "test_helper"

# Regression tests for the security review: each one pins a hole that was
# open before.
class SecurityTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @member = users(:member)
    @household = households(:smiths)
  end

  test "task titles are escaped in flash messages and on the schedule" do
    sign_in @member
    task = Task.create!(household: @household, title: "<img src=x onerror=alert(1)>", created_by: @member, assigned_to: @member)
    post start_task_path(task)
    follow_redirect!
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
    # The redirect honors the Host header, but the link inside the page must not.
    get URI(response.location).path
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
    [ admin_users_path, admin_settings_path, admin_households_path, admin_invitations_path ].each do |path|
      get path
      assert_response :forbidden, path
    end
  end

  test "members can't edit tasks someone else created" do
    task = Task.create!(household: @household, title: "Admin's", created_by: @admin)
    sign_in @member
    patch task_path(task), params: { task: { title: "Mine now" } }
    assert_response :forbidden
    assert_equal "Admin's", task.reload.title
  end

  test "the wall needs a signed-in member of that household" do
    get wall_path(@household.slug)
    assert_redirected_to new_user_session_path

    sign_in @admin
    get wall_path(@household.slug)
    assert_response :success
    assert_select ".person-card", 2
    get wall_path("not-a-token")
    assert_response :not_found
    sign_out @admin

    outsider = User.create!(email: "outsider@example.com", password: "password123", display_name: "Outsider")
    Household.create!(name: "Others").household_memberships.create!(user: outsider)
    sign_in outsider
    get wall_path(@household.slug)
    assert_response :not_found
  end

  test "signing in from the wall's link returns to the wall" do
    get wall_path(@household.slug)
    post user_session_path, params: { user: { email: @admin.email, password: "password" } }
    assert_redirected_to wall_path(@household.slug)
  end

  test "a member without a household sees a message, not a redirect loop" do
    @member.household_memberships.destroy_all
    sign_in @member
    get root_path
    assert_response :success
    assert_select "h1", "You're not in a household yet"
  end

  test "pages carry a content security policy" do
    sign_in @member
    get root_path
    policy = response.headers["Content-Security-Policy"]
    assert_match(/script-src 'self'/, policy)
    assert_match(/object-src 'none'/, policy)
  end

  test "there is no public sign-up route" do
    get "/users/sign_up"
    assert_response :not_found
  end

  test "photos need a signed-in person, and direct uploads are closed" do
    sign_in @member
    patch account_profile_path, params: { user: { avatar: fixture_file_upload("avatar.png", "image/png") } }
    path = Rails.application.routes.url_helpers.rails_blob_path(@member.reload.avatar, only_path: true)
    get path
    assert_response :redirect
    post rails_direct_uploads_path, params: { blob: { filename: "x.png", byte_size: 1, checksum: "x", content_type: "image/png" } }
    assert_response :forbidden

    sign_out @member
    get path
    assert_response :unauthorized
  end

  test "a clash with someone's private event doesn't name it to whoever saves" do
    starts = 2.days.from_now.change(hour: 10)
    Task.create!(household: @household, title: "Therapy", private: true, created_by: @admin, assigned_to: @admin,
                 starts_at: starts, ends_at: starts + 1.hour)
    sign_in @member
    post tasks_path, params: { task: { title: "Church", assignee_ids: [ @admin.id ], on_date: starts.to_date.iso8601, from_time: "10:00" } }
    follow_redirect!
    assert_select ".flash-notice", text: /Admin User has Busy then/
    assert_no_match(/Therapy/, response.body)
    assert_equal "Clashes with Therapy", Task.find_by!(title: "Church").assignment_for(@admin).conflict_note, "her own note names it"
  end

  test "an admin's security reset signs the person out everywhere" do
    sign_in @member
    get root_path
    assert_response :success

    @member.reset_sign_in_security!
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "a new password forgets every remembered device" do
    @member.remember_me!
    assert @member.remember_token

    @member.update!(password: "a-new-password")
    assert_nil @member.reload.remember_token
    assert_nil @member.remember_created_at
  end
end
