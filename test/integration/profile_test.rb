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

  test "getting started asks an admin to set up email before inviting, or skip it" do
    @member.update!(admin: true)

    get root_path
    titles = css_select(".checklist-step strong").map(&:text)
    assert_equal [ "Set up email", "Invite your family" ], titles.first(2)
    assert_select ".checklist-step:not(.is-done)", text: /Set up email/

    post skip_checklist_step_path("email")
    get root_path
    assert_select ".checklist-step.is-skipped", text: /Set up email/

    Setting.set("smtp_host", "smtp.example.com")
    get root_path
    assert_select ".checklist-step.is-done:not(.is-skipped)", text: /Set up email/
  end

  test "getting the wall link ticks off the tablet step" do
    @member.update!(admin: true)

    get root_path
    assert_select ".checklist-step:not(.is-done) form[action=?]", checklist_wall_link_path, text: /Get the wall link/

    post checklist_wall_link_path
    assert_redirected_to edit_admin_household_path(@smiths)
    get root_path
    assert_select ".checklist-step.is-done", text: /spare tablet/
  end

  test "the admin checklist steps are for admins only" do
    @member.update!(admin: false)

    get root_path
    assert_select ".checklist-step", text: /Set up email|spare tablet/, count: 0
    post skip_checklist_step_path("email")
    assert_response :not_found
    post checklist_wall_link_path
    assert_response :not_found
    assert_nil @member.reload.wall_link_opened_at
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

  test "a swatch sets the colour, and a custom colour wins over it" do
    { [ "#ec4899", "" ] => "#ec4899", [ "#22c55e", "123ABC" ] => "#123abc" }.each do |(color, custom), expected|
      patch account_profile_path, params: profile_params(color: color, custom_color: custom)
      assert_redirected_to account_root_path
      assert_equal expected, @member.reload.color
    end
  end

  test "a custom colour off the palette is shown in the custom box" do
    @member.update!(color: "#123abc")
    get account_root_path
    assert_select "details.custom-color[open] input[name='user[custom_color]'][value='#123abc']"
    assert_select "input[name='user[color]'][checked]", count: 0
  end

  test "saving the profile re-renders the person card on the board" do
    assert_turbo_stream_broadcasts [ @smiths, :members ] do
      patch account_profile_path, params: profile_params(color: "#ec4899", custom_color: "")
    end
  end

  test "uploading a photo shows it on the board" do
    patch account_profile_path, params: profile_params(avatar: fixture_file_upload("avatar.png", "image/png"))
    assert_redirected_to account_root_path
    assert @member.reload.avatar.attached?

    get root_path
    assert_select "#{card(@member)} .person-avatar img[src*='/rails/active_storage/']"
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
    { user: { display_name: @member.display_name }.merge(user) }
  end
end
