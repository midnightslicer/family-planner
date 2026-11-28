require "test_helper"

class WorkScheduleTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    @little = @smiths.locations.create!(name: "Little house", kind: "house")
  end

  def weekdays(from: "09:00", until_time: "17:00", place: "Little house")
    (1..5).to_h { |wday| [ wday.to_s, { on: "1", from_time: from, until_time: until_time, place: place } ] }
  end

  # Monday 2026-11-23.
  def monday_at(hour, min = 0) = Time.zone.local(2026, 11, 23, hour, min)

  test "nobody has to have a work schedule" do
    sign_in @member
    get tasks_path
    assert_select "a", text: "Add work hours"
    assert_select "button", text: "I'm off today", count: 0
    get root_path
    assert_select "#{card(@member)} .avail-free", text: "Free to call"
  end

  test "saving work hours, place and availability" do
    sign_in @member
    patch work_schedule_path, params: { work_schedule: { availability: "busy", days: weekdays } }
    assert_redirected_to edit_work_schedule_path
    assert_equal [ 1, 2, 3, 4, 5 ], @member.work_shifts.pluck(:weekday)
    assert_equal "busy", @member.reload.work_availability

    # Unticking a day removes it, and each save keeps a dated copy.
    patch work_schedule_path, params: { work_schedule: { availability: "text", days: weekdays.slice("1") } }
    assert_equal [ 1 ], @member.work_shifts.reload.pluck(:weekday)
    versions = @member.work_schedule_versions.order(:effective_at)
    assert_equal [ 5, 1 ], versions.map { |v| v.shifts.size }
    assert_equal %w[busy text], versions.map(&:availability)
    assert_equal({ "weekday" => 1, "from_time" => "09:00", "until_time" => "17:00", "place" => "Little house" }, versions.last.shifts.first)
  end

  test "work place is picked from Office, Remote and your houses, or typed under Other" do
    sign_in @member
    get edit_work_schedule_path
    assert_select "select[name='work_schedule[days][1][place]'] option", text: "Office"
    assert_select "select[name='work_schedule[days][1][place]'] option", text: "Little house"

    patch work_schedule_path, params: { work_schedule: { days: {
      "1" => { on: "1", from_time: "09:00", until_time: "17:00", place: "Office" },
      "2" => { on: "1", from_time: "09:00", until_time: "17:00", place: "new", place_other: "Client site" }
    } } }
    assert_equal [ "Office", "Client site" ], @member.work_shifts.order(:weekday).pluck(:place)
    assert_equal 1, @smiths.locations.count, "Office is only a label, not a location"

    get edit_work_schedule_path
    assert_select "select[name='work_schedule[days][1][place]'] option[selected]", text: "Office"
    assert_select "select[name='work_schedule[days][2][place]'] option[selected]", text: "Other…"
    assert_select "input[name='work_schedule[days][2][place_other]'][value='Client site']"
  end

  test "a bad time is explained and nothing changes" do
    sign_in @member
    patch work_schedule_path, params: { work_schedule: { days: { "1" => { on: "1", from_time: "nine", until_time: "17:00" } } } }
    assert_response :unprocessable_content
    assert_select ".flash-alert", text: /Monday/
    assert_equal 0, @member.work_shifts.count
  end

  test "during work hours the card shows work, its place and availability" do
    @member.update!(work_availability: "text")
    @member.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00", place: "Little house")
    travel_to monday_at(10) do
      sign_in @member
      get root_path
      assert_select "#{card(@member)} .avail-text", text: "Text only"
      # The section heading says where; the card doesn't repeat it.
      assert_select ".house-group", text: /Little house/ do
        assert_select "#{card(@member)} .person-now", text: "Work · until 5 PM"
      end
      assert_select "#{card(@member)} .person-where", count: 0

      get tasks_path
      assert_select ".sched-work .sched-title", text: "Work"
    end
  end

  test "a meeting during work shows instead of work" do
    @member.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00", place: "Remote")
    Task.create!(household: @smiths, title: "Standup", assigned_to: @member, availability: "busy",
                 starts_at: monday_at(10), ends_at: monday_at(10, 30))
    travel_to monday_at(10, 10) do
      sign_in @member
      get root_path
      assert_select "#{card(@member)} .person-now", text: "Standup · until 10:30 AM"
    end
  end

  test "I'm off today is one tap, the family sees it, and it can be undone" do
    @member.work_shifts.create!(weekday: 1, from_time: "09:00", until_time: "17:00")
    travel_to monday_at(10) do
      sign_in @member
      post days_off_path, params: { today: 1 }, headers: { "Referer" => tasks_url }
      assert_redirected_to tasks_url
      off = @member.days_off.sole
      assert_equal Date.new(2026, 11, 23), off.starts_on

      get tasks_path
      assert_select ".day-off-banner", text: /You're off today/
      assert_select ".sched-work", count: 0

      sign_in @admin
      get root_path
      # Only three statuses: a day off is Free, saying why underneath.
      assert_select "#{card(@member)} .status-chip.avail-free", text: "Free to call"
      assert_select "#{card(@member)} .person-now", text: "Day off"
      get tasks_path(person: "family")
      assert_select ".family-column .status-chip.avail-free", text: "Free to call"
      assert_select ".family-column .person-now", text: "Day off"

      sign_in @member
      delete day_off_path(off)
      assert_equal 0, @member.days_off.count
    end
  end

  test "a run of days off with a note shows as coming up" do
    travel_to monday_at(10) do
      sign_in @member
      post days_off_path, params: { day_off: { starts_on: "2026-12-24", ends_on: "2026-12-28", note: "Christmas" } }
      get tasks_path
      assert_select ".sched-day-off", text: /Day off · Christmas/
    end
  end

  test "you can only remove your own days off" do
    theirs = @admin.days_off.create!(starts_on: Date.current, ends_on: Date.current)
    sign_in @member
    delete day_off_path(theirs)
    assert_response :not_found
    assert DayOff.exists?(theirs.id)
  end

  test "a night shift runs past midnight" do
    @member.work_shifts.create!(weekday: 1, from_time: "22:00", until_time: "06:00")
    travel_to Time.zone.local(2026, 11, 24, 2, 0) do
      assert WorkBlock.current(@member.reload, Time.current)
    end
  end
end
