require "test_helper"

class InvitationJoinTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:smiths)
    @admin = users(:admin)
  end

  def invite(email: "sam@example.com")
    Invitation.create!(email: email, household: @household, invited_by: @admin)
  end

  test "joining with a password creates the account and membership" do
    invitation = invite
    get invitation_path(invitation.raw_token)
    assert_response :success
    assert_select "input[name='user[email]'][readonly][value=?]", "sam@example.com"

    post join_invitation_path(invitation.raw_token),
         params: { user: { display_name: "Sam", email: "hacker@example.com", password: "long enough pw", color: "#22c55e" } }
    assert_redirected_to dashboard_path

    user = User.find_by!(email: "sam@example.com")
    assert user.member_of?(@household)
    assert invitation.reload.accepted?
  end

  test "joining with a passkey needs no password" do
    invitation = invite
    authenticator = new_authenticator
    fields = { user: { display_name: "Sam", color: "#22c55e" } }
    post invitation_passkey_options_path(invitation.raw_token), params: fields
    assert_response :success

    credential = authenticator.create(challenge: response.parsed_body["challenge"])
    post join_invitation_path(invitation.raw_token), params: fields.merge(passkey_credential: credential.to_json)
    assert_redirected_to dashboard_path

    user = User.find_by!(email: "sam@example.com")
    assert_not user.password_set?
    assert_equal 1, user.passkeys.count
  end

  test "a link-only invitation lets the person enter their email" do
    invitation = invite(email: "")
    assert_nil invitation.email
    post join_invitation_path(invitation.raw_token),
         params: { user: { display_name: "Kid", email: "kid@example.com", password: "long enough pw" } }
    assert_redirected_to dashboard_path
    assert User.exists?(email: "kid@example.com")
  end

  test "an invitation works once" do
    invitation = invite
    token = invitation.raw_token
    post join_invitation_path(token), params: { user: { display_name: "Sam", password: "long enough pw" } }
    delete destroy_user_session_path

    get invitation_path(token)
    assert_response :not_found
    post join_invitation_path(token), params: { user: { display_name: "Sam 2", password: "long enough pw" } }
    assert_response :not_found
    assert_equal 1, User.where(email: "sam@example.com").count
  end

  test "a failed join doesn't use up the invitation" do
    invitation = invite
    post join_invitation_path(invitation.raw_token), params: { user: { display_name: "", password: "short" } }
    assert_response :unprocessable_content
    assert invitation.reload.pending?
  end

  test "someone signed in joins with one click" do
    other = Household.create!(name: "Grandma's")
    invitation = Invitation.create!(email: users(:member).email, household: other, invited_by: @admin)
    sign_in users(:member)

    get invitation_path(invitation.raw_token)
    assert_select "button", text: "Join Grandma's"
    post accept_invitation_path(invitation.raw_token)
    assert_redirected_to dashboard_path
    assert users(:member).member_of?(other)
  end

  test "an invitation for someone else can't be accepted" do
    invitation = invite(email: "sam@example.com")
    sign_in users(:member)
    post accept_invitation_path(invitation.raw_token)
    assert invitation.reload.pending?
  end

  test "an existing account is asked to sign in first" do
    invitation = invite(email: users(:member).email)
    get invitation_path(invitation.raw_token)
    assert_select "h1", "You already have an account"
  end
end
