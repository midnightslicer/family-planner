require "test_helper"
require "turbo/broadcastable/test_helper"

class ProfileTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @member = users(:member) # color #22c55e, a palette colour
    @smiths = households(:smiths)
    sign_in @member
  end

  # Regression: the custom box used to post user[color] too, prefilled with
  # the old colour, and as the later field it overrode the chosen swatch.
  test "only the swatches post user[color]; the custom box starts empty" do
    get account_root_path
    assert_response :success
    assert_select "input[name='user[color]']:not([type=radio])", count: 0
    assert_select "input[name='user[color]'][type=radio][checked][value='#22c55e']"
    assert_select "input[name='user[custom_color]']:not([value])"
  end

  test "getting started stays at the bottom of the account page, done steps too, until it's all done" do
    @member.update_column(:onboarding_dismissed_at, Time.current) # hidden on the dashboard
    @smiths.tasks.destroy_all
    Task.create!(household: @smiths, title: "Call the vet", assigned_to: @member)

    get account_root_path
    assert_select ".checklist", 1
    assert_select ".checklist-header button", count: 0 # no Hide here
    assert_select ".checklist-step.is-done", text: /Put something on your schedule/
    assert_select ".checklist-step:not(.is-done)", text: /signing in quicker/

    @member.update!(otp_secret: "JBSWY3DPEHPK3PXP", otp_enabled_at: Time.current)
    @member.avatar.attach(io: file_fixture("avatar.png").open, filename: "avatar.png")
    @member.household_memberships.find_by(household: @smiths).update!(home: @smiths.locations.create!(name: "Red Brick", kind: "house"))
    get account_root_path
    assert_select ".checklist-step:not(.is-done)", 1
    assert_select ".checklist-step:not(.is-done)", text: /work schedule/

    # No work schedule: skip it and the list is done.
    post skip_checklist_step_path("work"), headers: { "HTTP_REFERER" => account_root_url }
    assert_redirected_to account_root_url
    get account_root_path
    assert_select ".checklist", count: 0
    post skip_checklist_step_path("nope")
    assert_response :not_found
  end

  test "the app takes its accent from the signed-in person's colour" do
    get account_root_path
    theme = ColorTheme.for("#22c55e")
    assert_select "style#theme-tokens", text: /--accent:#{theme.light["--accent"]}.*prefers-color-scheme: dark.*--accent:#{theme.dark["--accent"]}/
    assert_select "meta[name=theme-color][content='#{theme.surface(:dark)}']"

    @member.update!(color: "#ec4899")
    get account_root_path
    assert_select "style#theme-tokens", text: /--accent:#{ColorTheme.for("#ec4899").light["--accent"]}/
  end

  test "signed-out pages keep the default colours" do
    sign_out @member
    get new_user_session_path
    assert_select "style#theme-tokens", count: 0
  end

  test "picking a swatch changes the colour" do
    patch account_profile_path, params: profile_params(color: "#ec4899", custom_color: "")
    assert_redirected_to account_root_path
    assert_equal "#ec4899", @member.reload.color
  end

  test "a custom colour wins over the swatch" do
    patch account_profile_path, params: profile_params(color: "#22c55e", custom_color: "123ABC")
    assert_equal "#123abc", @member.reload.color
  end

  test "a custom colour off the palette is shown in the custom box" do
    @member.update!(color: "#123abc")
    get account_root_path
    assert_select "details.custom-color[open] input[name='user[custom_color]'][value='#123abc']"
    assert_select "input[name='user[color]'][checked]", count: 0
  end

  test "the colour picked when joining sticks too" do
    sign_out @member
    invitation = Invitation.create!(email: "sam@example.com", household: @smiths, invited_by: users(:admin))
    get invitation_path(invitation.raw_token)
    assert_select "input[name='user[custom_color]']:not([value])"

    post join_invitation_path(invitation.raw_token),
         params: { user: { display_name: "Sam", password: "long enough pw", color: "#f97316", custom_color: "" } }
    assert_equal "#f97316", User.find_by!(email: "sam@example.com").color
  end

  test "saving the profile re-renders the person card on the board" do
    assert_turbo_stream_broadcasts [@smiths, :members] do
      patch account_profile_path, params: profile_params(color: "#ec4899", custom_color: "")
    end
  end

  test "uploading a photo shows it on the board" do
    patch account_profile_path, params: profile_params(avatar: fixture_file_upload("avatar.png", "image/png"))
    assert_redirected_to account_root_path
    assert @member.reload.avatar.attached?

    get dashboard_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(@member, :person_card)} .person-avatar img[src*='/rails/active_storage/']"
  end

  test "a file that isn't a picture is refused, whatever it claims to be" do
    fake = Rack::Test::UploadedFile.new(StringIO.new("<svg onload=alert(1)>"), "image/png", original_filename: "x.png")
    patch account_profile_path, params: profile_params(avatar: fake)
    assert_response :unprocessable_content
    assert_match "Photo must be a JPEG, PNG or WebP image", response.body
    assert_not @member.reload.avatar.attached?
  end

  test "a photo can be removed" do
    @member.avatar.attach(io: file_fixture("avatar.png").open, filename: "avatar.png", content_type: "image/png")
    patch account_profile_path, params: profile_params(remove_avatar: "1")
    assert_not @member.reload.avatar.attached?
  end

  private

  def profile_params(**user)
    { user: { display_name: @member.display_name, handle: @member.handle }.merge(user) }
  end
end
