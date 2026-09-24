require "test_helper"

class SetupFlowTest < ActionDispatch::IntegrationTest
  setup do
    Task.delete_all
    HouseholdMembership.delete_all
    Invitation.delete_all
    User.delete_all
    Household.delete_all
  end

  def unlock
    post setup_unlock_path, params: { code: AppSettings.setup_code }
    assert_redirected_to setup_path
  end

  def account_params(**overrides)
    { household_name: "The Smiths",
      user: { display_name: "Alex Smith", email: "alex@example.com", password: "correct horse battery", color: "#22c55e" } }
      .deep_merge(overrides)
  end

  test "every page leads to setup until the first account exists" do
    get dashboard_path
    assert_redirected_to setup_path
    get new_user_session_path
    assert_redirected_to setup_path
  end

  test "setup asks for the code from the server log" do
    get setup_path
    assert_response :success
    assert_select "input[name=code]"
    assert_select "input[name='user[email]']", count: 0

    post setup_unlock_path, params: { code: "nope-nope-nope-nope" }
    assert_response :unprocessable_content

    post setup_path, params: account_params
    assert_response :forbidden
    assert_not User.exists?
  end

  test "the code works in the link, and in any case or spacing" do
    get setup_path(code: AppSettings.setup_code.upcase.tr("-", " "))
    assert_redirected_to setup_path
    follow_redirect!
    assert_select "input[name='user[email]']"
  end

  test "creates the admin, household and settings with a password" do
    unlock
    post setup_path, params: account_params
    assert_redirected_to dashboard_path

    user = User.sole
    assert user.admin?
    assert_equal "alex_smith", user.handle
    assert_equal ["The Smiths"], user.households.map(&:name)
    assert_equal "The Smiths", AppSettings.app_name
    assert_equal "http://www.example.com", Setting.get("app_url")

    follow_redirect!
    assert_select ".checklist"
    assert_select ".person-card", 1
  end

  test "creates the admin with a passkey and no password" do
    unlock
    authenticator = new_authenticator
    post setup_passkey_options_path, params: account_params
    assert_response :success
    options = response.parsed_body
    assert_equal "www.example.com", options.dig("rp", "id")

    credential = authenticator.create(challenge: options["challenge"])
    post setup_path, params: account_params(user: { password: "" }).merge(passkey_credential: credential.to_json)
    assert_redirected_to dashboard_path

    user = User.sole
    assert_not user.password_set?
    assert_equal [authenticator.encoded_id], user.passkeys.pluck(:external_id)
    assert_equal options.dig("user", "id"), user.webauthn_id
  end

  test "passkey options report profile errors before the passkey is made" do
    unlock
    post setup_passkey_options_path, params: account_params(user: { email: "not-an-email" })
    assert_response :unprocessable_content
    assert_match(/Email/, response.parsed_body["error"])
  end

  test "setup closes once an account exists" do
    unlock
    post setup_path, params: account_params
    delete destroy_user_session_path

    get setup_path
    assert_redirected_to dashboard_path
    post setup_path, params: account_params(user: { email: "intruder@example.com" })
    assert_equal 1, User.count
  end
end
