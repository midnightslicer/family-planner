require "test_helper"

# The version on the account page and "What's new" after an update.
class ChangelogTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    sign_in @member
  end

  test "after an update it opens by itself once; closing it keeps it away until the next one" do
    @member.update_column(:last_seen_version, nil) # here before this version
    get root_path
    assert_select "dialog#changelog[data-changelog-auto-value=true]"
    assert_select "#changelog .changelog-release h3", text: /Version #{Regexp.escape(AppVersion::CURRENT)}/
    assert_select "#changelog li", minimum: 1

    post seen_account_changelog_path
    assert_response :no_content
    assert_equal AppVersion::CURRENT, @member.reload.last_seen_version
    get root_path
    assert_select "dialog#changelog[data-changelog-auto-value=false]" # still there to open by hand

    @member.update_column(:last_seen_version, "1.0")
    assert AppVersion.unseen_by?(@member)
    @member.update_column(:last_seen_version, "1.10")
    assert_not AppVersion.unseen_by?(@member), "versions compare as numbers, not text"
  end

  test "the account page ends with the version, which opens what's new" do
    get account_root_path
    assert_select ".app-version [data-changelog-open]", text: /Version #{Regexp.escape(AppVersion::CURRENT)}/
  end

  test "a new account isn't told about changes from before it joined" do
    user = User.create!(email: "new@example.test", password: "password123456", display_name: "New")
    assert_equal AppVersion::CURRENT, user.last_seen_version
  end

  test "signed out, there's nothing to show" do
    sign_out @member
    get new_user_session_path
    assert_select "#changelog", count: 0
    post seen_account_changelog_path
    assert_response :redirect
  end

  test "every release has a version and changes, newest first, starting with this one" do
    releases = AppVersion.changelog
    assert_equal AppVersion::CURRENT, releases.first[:version]
    releases.each { |release| assert release[:version].present? && release[:changes].present? }
    versions = releases.map { |release| Gem::Version.new(release[:version]) }
    assert_equal versions.sort.reverse, versions
  end
end
