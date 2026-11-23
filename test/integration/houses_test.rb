require "test_helper"

class HousesTest < ActionDispatch::IntegrationTest
  setup do
    @me = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    @brick = @smiths.locations.create!(name: "Red Brick House", kind: "house")
    @ours = @smiths.locations.create!(name: "Our House", kind: "house")
    sign_in @me
  end

  def profile_params(**extra)
    { user: { display_name: @me.display_name, handle: @me.handle, color: @me.color, custom_color: "" } }.merge(extra)
  end

  test "the board stays one group until someone has a house" do
    get dashboard_path
    assert_select ".house-title", count: 0
    assert_select ".person-card", 2
  end

  test "the profile picks your house from photo tiles, including Not set and a new house" do
    get account_root_path
    assert_select ".picker-field .pick-tile input[name=home_id]", count: 4 # Not set, two houses, New house
    assert_select ".pick-tile .pick-name", text: "Our House"
    assert_select ".pick-tile .pick-name", text: "New house"
    assert_select "select#home_id", count: 0
  end

  test "you pick the house you live in, and the board groups by house" do
    patch account_profile_path, params: profile_params(home_id: @ours.id)
    assert_equal @ours, @me.home_in(@smiths)
    @smiths.pets.create!(name: "Rex", home: @brick)

    get dashboard_path
    assert_select ".house-title", text: /Our House/
    assert_select ".house-title", text: /Red Brick House/
    assert_select ".house-title", text: /No house set/
    assert_select ".house-group", text: /Our House/ do
      assert_select ".person-card", 1
    end
    assert_select ".house-group", text: /Red Brick House/ do
      assert_select ".pet-card", 1
    end
  end

  test "a new house can be added right from the account page" do
    patch account_profile_path, params: profile_params(home_id: "new", new_home_name: "Little house")
    home = @me.home_in(@smiths)
    assert_equal "Little house", home.name
    assert home.house?
  end

  test "admins set where each member lives" do
    sign_in @admin
    membership = @smiths.household_memberships.find_by!(user: @me)
    patch admin_household_membership_path(@smiths, membership), params: { household_membership: { home_id: @brick.id } }
    assert_equal @brick, membership.reload.home
  end

  test "the family view and locations show who lives where" do
    @smiths.household_memberships.find_by!(user: @me).update!(home: @ours)
    get tasks_path(person: "family")
    assert_select ".house-title", text: /Our House/
    get locations_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(@ours)} .task-meta", text: /Home to Member/
  end

  test "moving house keeps where they lived before" do
    membership = @smiths.household_memberships.find_by!(user: @me)
    travel_to(Time.zone.local(2026, 1, 1)) { membership.update!(home: @ours) }
    travel_to(Time.zone.local(2026, 6, 1)) { membership.update!(home: @brick) }
    travel_to(Time.zone.local(2026, 9, 1)) { @brick.archive! }

    history = @me.residences.order(:started_at).map { |r| [r.location.name, r.started_at.to_date, r.ended_at&.to_date] }
    assert_equal [["Our House", Date.new(2026, 1, 1), Date.new(2026, 6, 1)],
                  ["Red Brick House", Date.new(2026, 6, 1), Date.new(2026, 9, 1)]], history
  end

  test "deleting a house leaves its people with no house set" do
    membership = @smiths.household_memberships.find_by!(user: @me)
    membership.update!(home: @ours)
    @ours.destroy
    assert_nil membership.reload.home_id
  end
end
