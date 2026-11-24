require "test_helper"

class StatusTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    sign_in @member
  end

  def card = "##{ActionView::RecordIdentifier.dom_id(@member, :person_card)}"

  test "your day has one-tap status chips; none is lit until you set one" do
    get tasks_path
    assert_select ".status-bar .where-chip", 3
    assert_select ".status-bar .where-chip.is-current", count: 0
    assert_select ".status-bar", text: /Free/
    assert_no_match(/free to call/i, response.body)

    post status_me_path, params: { availability: "busy" }, headers: { "Referer" => tasks_url }
    assert_redirected_to tasks_url
    get tasks_path
    assert_select ".status-bar .where-chip.is-current", text: "Do not disturb"
    assert_select ".status-until", text: /Until/

    get dashboard_path
    assert_select "#{card}.is-busy .avail-busy", text: /Do not disturb/
  end

  test "it lasts 12 hours, then you're back to your schedule" do
    post status_me_path, params: { availability: "text" }
    travel 11.hours + 59.minutes
    get dashboard_path
    assert_select "#{card} .avail-text", text: /Text only/
    travel 2.minutes
    get dashboard_path
    assert_select "#{card} .avail-text", count: 0
    assert_select "#{card}:not(.is-busy) .avail-free"
  end

  test "what you set wins over an event, Free included" do
    Task.create!(household: @smiths, title: "Dentist", assigned_to: @member, availability: "text",
                 starts_at: 10.minutes.ago, ends_at: 50.minutes.from_now)
    post status_me_path, params: { availability: "busy" }
    get dashboard_path
    assert_select "#{card} .status-chip", text: /Do not disturb/
    assert_select "#{card} .avail-text", count: 0 # the event's chip gives way
    assert_select "#{card} .person-now", text: /Dentist/

    post status_me_path, params: { availability: "free" }
    get dashboard_path
    assert_select "#{card}:not(.is-busy) .avail-free", text: /Free/
    assert_select "#{card} .avail-text", count: 0
    assert_equal 2, @member.status_updates.count # history kept
  end

  test "what you set wins over your work hours" do
    @smiths.update!(time_zone: "Central Time (US & Canada)")
    @member.update!(work_availability: "busy")
    @member.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00", place: "Office")
    travel_to Time.utc(2026, 11, 23, 16, 0) do # Monday 10 AM in Chicago
      get dashboard_path
      assert_select "#{card}.is-busy .avail-busy"

      post status_me_path, params: { availability: "free" }
      get dashboard_path
      assert_select "#{card}:not(.is-busy) .avail-free", text: /Free/
      assert_select "#{card} .avail-busy", count: 0
      assert_select "#{card} .person-now", text: /Work/
      get tasks_path
      assert_select ".status-bar .where-chip.is-current", text: "Free"
    end
  end

  test "every status chip is one of three, Free always with the sun" do
    Task.create!(household: @smiths, title: "Mowing", assigned_to: @member, availability: "free",
                 starts_at: 10.minutes.ago, ends_at: 50.minutes.from_now)
    get dashboard_path
    labels = css_select(".person-card .status-chip").map { |chip| chip.text.strip }.uniq
    assert_empty labels - ["Free", "Text only", "Do not disturb"]
    css_select(".person-card .avail-free").each { |chip| assert_select chip, ".icon-sun" }
  end

  test "tapping the lit chip again goes back to your work hours" do
    @smiths.update!(time_zone: "Central Time (US & Canada)")
    @member.update!(work_availability: "busy")
    @member.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00", place: "Office")
    travel_to Time.utc(2026, 11, 23, 16, 0) do
      post status_me_path, params: { availability: "free" }
      get tasks_path
      assert_select ".status-bar .where-chip.is-current", text: "Free"
      assert_select ".status-bar form:has(.is-current) input[name=availability][value=clear]"

      post status_me_path, params: { availability: "clear" }, headers: { "Referer" => tasks_url }
      assert_redirected_to tasks_url
      assert_equal "Back to your schedule.", flash[:notice]
      get tasks_path
      assert_select ".status-bar .where-chip.is-current", count: 0
      get dashboard_path
      assert_select "#{card}.is-busy .avail-busy" # work's Do not disturb again
      assert_equal 2, @member.status_updates.count # kept as history
    end
  end

  test "the wall shows it too" do
    post status_me_path, params: { availability: "busy" }
    get wall_path(@smiths.slug)
    assert_select "#{card} .avail-busy"
  end

  test "only ever your own status, and only real ones" do
    post status_me_path, params: { availability: "busy", user_id: @admin.id }
    assert_equal 0, @admin.status_updates.count # it set the member's own instead
    assert_equal 1, @member.status_updates.count
    post status_me_path, params: { availability: "asleep" }
    assert_equal 1, @member.status_updates.count
    assert_equal "Pick how reachable you are.", flash[:alert]
  end

  test "someone else's day has no status chips" do
    get tasks_path(person: @admin.id)
    assert_select ".status-bar", count: 0
  end
end
