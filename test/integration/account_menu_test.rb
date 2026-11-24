require "test_helper"

class AccountMenuTest < ActionDispatch::IntegrationTest
  setup { @smiths = households(:smiths) }

  test "every member finds the wall link on their account page" do
    sign_in users(:member)
    get account_root_path
    assert_select "#wall input[value*=?]", "/h/#{@smiths.slug}"
    assert_select "#wall button", text: "Make a new link", count: 0
  end

  test "the avatar menu holds the account and sign-out links, plus Admin for admins" do
    sign_in users(:member)
    get root_path
    assert_select ".user-menu .user-menu-header", text: /Member User/
    assert_select ".user-menu a[href=?]", account_root_path
    assert_select ".user-menu form[action=?]", destroy_user_session_path
    assert_select "a[href=?]", admin_root_path, count: 0

    sign_out users(:member)
    sign_in users(:admin)
    get root_path
    assert_select ".user-menu a[href=?]", admin_root_path
    assert_select ".nav-links a[href=?]", admin_root_path, count: 0
  end

  test "the main pages are in the top nav and, for phones, the tab bar, with the current one marked" do
    sign_in users(:member)
    get pets_path
    assert_select ".nav-links a", count: 3 # Home is the brand up there
    assert_select ".tab-bar[data-controller=tab-bar] .tab-bar-link", count: 4
    assert_select ".tab-bar a[href=?]", root_path, text: "Home"
    assert_select ".tab-bar a[aria-current=page]", count: 1, text: "Pets"

    sign_out users(:member)
    get new_user_session_path
    assert_select ".tab-bar", count: 0
  end
end
