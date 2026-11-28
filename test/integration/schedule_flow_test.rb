require "test_helper"

class ScheduleFlowTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    sign_in @member
  end

  test "the schedule has no cached preview, so the permanent quick add isn't doubled by the morph" do
    get tasks_path
    assert_select "meta[name=turbo-cache-control][content=no-preview]"
    assert_select "form.quick-add", 1
  end

  test "quick add puts a to-do on your own list" do
    post tasks_path, params: { task: { title: "Call the doctor", assignee_ids: [ @member.id ] } }
    assert_redirected_to tasks_path
    task = Task.find_by!(title: "Call the doctor")
    assert task.planned?
    assert_not task.timed?
    assert_equal @member, task.created_by

    follow_redirect!
    assert_select ".sched-todo .sched-title", text: "Call the doctor"
  end

  test "a time makes it an event, an hour long unless an end is given" do
    travel_to Time.zone.local(2026, 11, 22, 8, 0) do
      post tasks_path, params: { task: { title: "Church", assignee_ids: [ @member.id ], on_date: "2026-11-22", from_time: "10:00" } }
      church = Task.find_by!(title: "Church")
      assert_equal Time.zone.local(2026, 11, 22, 10, 0), church.starts_at
      assert_equal Time.zone.local(2026, 11, 22, 11, 0), church.ends_at

      post tasks_path, params: { task: { title: "Late shift", assignee_ids: [ @member.id ], from_time: "22:00", until_time: "01:00" } }
      shift = Task.find_by!(title: "Late shift")
      assert_equal Time.zone.local(2026, 11, 23, 1, 0), shift.ends_at
    end
  end

  test "a day without a time holds a to-do back until then" do
    travel_to Time.zone.local(2026, 11, 22, 8, 0) do
      post tasks_path, params: { task: { title: "Email Bob", assignee_ids: [ @member.id ], on_date: "2026-11-25" } }
      get tasks_path
      assert_select ".schedule-columns .sched-todo .sched-title", text: "Email Bob", count: 0
      assert_select ".section-title", text: /Coming up/
      assert_select ".sched-title", text: "Email Bob"
    end
  end

  test "ticking off a to-do needs no start first" do
    task = Task.create!(household: @smiths, title: "Dishes", assigned_to: @member)
    post complete_task_path(task)
    assert task.reload.completed?
  end

  test "an event on now shows on the card with its availability, by itself" do
    travel_to Time.zone.local(2026, 11, 22, 14, 0) do
      Task.create!(household: @smiths, title: "Client call", assigned_to: @member, availability: "busy",
                   starts_at: Time.zone.local(2026, 11, 22, 13, 30), ends_at: Time.zone.local(2026, 11, 22, 15, 0))
      Task.create!(household: @smiths, title: "Grocery run", assigned_to: @admin, availability: "text", place: "Town",
                   starts_at: Time.zone.local(2026, 11, 22, 13, 0), ends_at: Time.zone.local(2026, 11, 22, 16, 0))

      get root_path
      member_card = card(@member)
      assert_select "#{member_card} .avail-busy", text: "Do not disturb"
      assert_select "#{member_card} .person-now", text: "Client call · until 3 PM"
      admin_card = card(@admin)
      assert_select "#{admin_card} .avail-text", text: "Text only"
      assert_select "#{admin_card} .person-now", text: "Grocery run · until 4 PM · Town"
    end
  end

  test "with nothing on, a card says free and what's next" do
    travel_to Time.zone.local(2026, 11, 22, 8, 0) do
      Task.create!(household: @smiths, title: "Church", assigned_to: @member,
                   starts_at: Time.zone.local(2026, 11, 22, 10, 0), ends_at: Time.zone.local(2026, 11, 22, 11, 0))
      get root_path
      card = card(@member)
      assert_select "#{card} .avail-free", text: "Free to call"
      assert_select "#{card} .person-next", text: "Next: Church · 10 AM"
    end
  end

  test "you can look at someone else's day and the whole family's" do
    Task.create!(household: @smiths, title: "Admin's errand", assigned_to: @admin)
    get tasks_path(person: @admin.id)
    assert_select "h1", text: "Admin User's day"
    assert_select ".sched-title", text: "Admin's errand"
    assert_select "input[name='task[assignee_ids][]'][value='#{@admin.id}'][checked]"

    get tasks_path(person: "family")
    assert_select ".family-column", 2
  end

  test "a recurring event that ended unmarked comes round again by itself" do
    travel_to Time.zone.local(2026, 11, 22, 12, 0) do
      Task.create!(household: @smiths, title: "Church", assigned_to: @member, recurrence_interval: "weekly",
                   starts_at: Time.zone.local(2026, 11, 8, 10, 0), ends_at: Time.zone.local(2026, 11, 8, 11, 0))
      get tasks_path
      upcoming = Task.where(title: "Church").planned.sole
      assert_equal Time.zone.local(2026, 11, 29, 10, 0), upcoming.starts_at
      assert_equal 3, Task.where(title: "Church").completed.count # Nov 8, 15 and 22 (over by noon)
    end
  end

  test "a started to-do's banner shows when it started as text, not markup" do
    task = Task.create!(household: @smiths, title: "Call the chiropractor", assigned_to: @member)
    task.start!
    get tasks_path
    assert_select ".now-banner small time", text: "just now"
    assert_no_match(/&lt;time/, response.body)
  end

  test "the assignee can edit an item someone else gave them" do
    task = Task.create!(household: @smiths, title: "From admin", assigned_to: @member, created_by: @admin)
    patch task_path(task), params: { task: { title: "Mine to change" } }
    assert_equal "Mine to change", task.reload.title
  end

  test "the quick add answers with a stream: just the lists and the flash, the box stays put" do
    post tasks_path, params: { stay: 1, person: @member.id, task: { title: "Buy milk", assignee_ids: [ @member.id ] } },
                     as: :turbo_stream
    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action=replace][target=schedule-lists] .sched-title", text: "Buy milk"
    assert_select "turbo-stream[action=replace][target=schedule-top]"
    assert_select "turbo-stream[action=update][target=flash]", text: /Buy milk/
    assert_select "form.quick-add", count: 0
  end

  test "the quick add survives the page's refreshes" do
    get tasks_path
    assert_select "form.quick-add#quick-add-#{@member.id}[data-turbo-permanent]"
  end

  test "where: one of your locations from the menu, or Other for a place that isn't saved" do
    pool = @smiths.locations.create!(name: "Pool", kind: "pool")
    get tasks_path
    assert_select "select[name='task[place_choice]'] option[value='Pool']"
    assert_select "select[name='task[place_choice]'] option[value='other']", text: "Other…"
    assert_select "input[name='task[place]']", count: 0

    post tasks_path, params: { task: { title: "Swim", place_choice: "Pool", place_other: "", from_time: "15:00", assignee_ids: [ @member.id ] } }
    assert_equal [ "Pool", pool ], Task.find_by!(title: "Swim").then { |t| [ t.place, t.location ] }

    assert_no_difference -> { @smiths.locations.count } do
      post tasks_path, params: { task: { title: "Dentist", place_choice: "other", place_other: "Dr. Lee", from_time: "16:00", assignee_ids: [ @member.id ] } }
    end
    dentist = Task.find_by!(title: "Dentist")
    assert_equal "Dr. Lee", dentist.place
    assert_nil dentist.location

    get edit_task_path(dentist)
    assert_select "select[name='task[place_choice]'] option[selected][value='other']"
    assert_select "input[name='task[place_other]'][value='Dr. Lee']"
  end
end
