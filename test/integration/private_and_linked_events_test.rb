require "test_helper"

class PrivateAndLinkedEventsTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    @little = @smiths.locations.create!(name: "Little house", kind: "house")
  end

  test "others see a private event only as busy, with its availability" do
    travel_to Time.zone.local(2026, 11, 22, 14, 0) do
      Task.create!(household: @smiths, title: "Therapy", place: "Dr. Lee", assigned_to: @admin, created_by: @admin,
                   private: true, availability: "busy",
                   starts_at: Time.zone.local(2026, 11, 22, 13, 30), ends_at: Time.zone.local(2026, 11, 22, 15, 0))
      sign_in @member

      get root_path
      assert_select "#{card(@admin)} .person-now", text: "Busy · until 3 PM"
      assert_select "#{card(@admin)} .avail-busy"
      assert_no_match(/Therapy|Dr\. Lee/, response.body)

      get tasks_path(person: @admin.id)
      assert_select ".sched-item.is-private .sched-title", text: "Busy"
      assert_no_match(/Therapy|Dr\. Lee/, response.body)

      get tasks_path(person: "family")
      assert_no_match(/Therapy|Dr\. Lee/, response.body)
    end
  end

  test "private to-dos are hidden from others and can't be opened" do
    secret = Task.create!(household: @smiths, title: "Buy Mom's present", assigned_to: @admin, created_by: @admin, private: true)
    sign_in @member
    get tasks_path(person: @admin.id)
    assert_no_match(/Mom's present/, response.body)
    get task_path(secret)
    assert_response :not_found
    post complete_task_path(secret)
    assert_response :not_found
    assert secret.reload.planned?
  end

  test "the private box saves from the form, and you see your own private items in full" do
    sign_in @member
    post tasks_path, params: { task: { title: "Buy Mom's present", assignee_ids: [@member.id], private: "1" } }
    assert Task.find_by!(title: "Buy Mom's present").private?
    get tasks_path
    assert_select ".sched-title", text: "Buy Mom's present"
    assert_select ".sched-title .private-mark"
  end

  test "an event at one of your locations puts you there while it's on" do
    # Said they were at the big house before the event began; the event,
    # newer, puts them at the little one (a report after it began would win).
    travel_to Time.zone.local(2026, 11, 22, 13, 0) do
      LocationReport.create!(household: @smiths, subject: @admin, reported_by: @admin,
                             location: @smiths.locations.create!(name: "Big house", kind: "house"))
    end
    travel_to Time.zone.local(2026, 11, 22, 14, 0) do
      event = Task.create!(household: @smiths, title: "Client meeting", place: "little HOUSE", assigned_to: @admin,
                           starts_at: Time.zone.local(2026, 11, 22, 13, 30), ends_at: Time.zone.local(2026, 11, 22, 15, 0))
      assert_equal @little, event.location

      sign_in @member
      get root_path
      assert_select "##{dom_id(@little, :board_place)} #{card(@admin)} .person-now", text: "Client meeting · until 3 PM"

      get tasks_path(person: @admin.id)
      assert_select ".day-where", text: /Little house · until 3 PM/

      get locations_path
      assert_select "##{dom_id(@little)} .here-now", text: /Admin User/
    end

    travel_to Time.zone.local(2026, 11, 22, 16, 0) do
      reset! # two hours on, the old session has timed out
      sign_in @member
      get root_path
      assert_select ".house-group", text: /Big house/ do
        assert_select card(@admin)
      end
    end
  end

  test "renaming a location carries through to its events" do
    event = Task.create!(household: @smiths, title: "Lunch", place: "Little house", assigned_to: @admin,
                         starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
    @little.update!(name: "Guest house")
    assert_equal "Guest house", event.reload.place_name
  end

  test "a private event doesn't reveal where it is" do
    travel_to Time.zone.local(2026, 11, 22, 14, 0) do
      Task.create!(household: @smiths, title: "Nap", place: "Little house", assigned_to: @admin, private: true,
                   starts_at: Time.zone.local(2026, 11, 22, 13, 30), ends_at: Time.zone.local(2026, 11, 22, 15, 0))
      sign_in @member
      get root_path
      assert_select "#{card(@admin)} .person-where", count: 0
    end
  end
end
