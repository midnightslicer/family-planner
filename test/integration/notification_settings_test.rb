require "test_helper"

class NotificationSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:member)
    @admin = users(:admin)
    sign_in @member
  end

  def smtp_on! = Setting.set("smtp_host", "smtp.example.com")

  def matrix(**rows)
    { categories: rows.transform_values { |push, email| { push: push ? "1" : "0", email: email ? "1" : "0" } } }
  end

  test "with no saved rows, everyone gets the defaults" do
    prefs = NotificationPreference.matrix_for(@member).index_by(&:category)
    assert_equal NotificationPreference::CATEGORIES.keys, prefs.keys
    assert prefs["assigned"].push
    assert prefs["assigned"].email
    assert prefs["pets"].push
    assert_not prefs["pets"].email
    assert_not prefs["todo_digest"].push
    assert prefs.values.all?(&:new_record?)
  end

  test "the page shows a row per category with accessible checkboxes" do
    get account_notifications_path
    assert_response :success
    NotificationPreference::CATEGORIES.each_value do |category|
      assert_select "th[scope=row]", text: /#{Regexp.escape(category.label)}/
      assert_select "label.visually-hidden[for=push_#{category.key}]", text: "Push: #{category.label}"
      assert_select "label.visually-hidden[for=email_#{category.key}]", text: "Email: #{category.label}"
    end
    assert_select "select[name='notifications[reminder_lead_minutes]']"
    assert_select "select[name='notifications[digest_hour]']"
    assert_select ".matrix-hints", text: /None of your devices get pushes yet/
  end

  test "saving the matrix creates and then updates rows" do
    smtp_on!
    patch account_notifications_path, params: { notifications: matrix(pets: [ false, true ], assigned: [ true, false ]) }
    assert_redirected_to account_notifications_path
    assert_equal [ false, true ], @member.notification_preference("pets").then { [ it.push, it.email ] }
    assert_equal [ true, false ], @member.reload.notification_preference("assigned").then { [ it.push, it.email ] }

    patch account_notifications_path, params: { notifications: matrix(pets: [ true, true ]) }
    assert_equal 1, @member.notification_preferences.where(category: "pets").count
    assert @member.reload.notification_preference("pets").push
  end

  test "unknown categories are ignored, and only your own settings change" do
    smtp_on!
    patch account_notifications_path, params: { notifications: matrix(hacking: [ true, true ]).deep_merge(user_id: @admin.id, categories: { pets: { push: "0" } }) }
    assert_redirected_to account_notifications_path
    assert_equal %w[pets], @member.notification_preferences.pluck(:category)
    assert_empty @admin.notification_preferences
  end

  test "lead time, digest hour and quiet hours only take allowed values" do
    patch account_notifications_path, params: { notifications: { reminder_lead_minutes: "30", digest_hour: "6" } }
    assert_redirected_to account_notifications_path
    assert_equal [ 30, 6 ], @member.reload.then { [ it.reminder_lead_minutes, it.digest_hour ] }

    [ { reminder_lead_minutes: "7" }, { digest_hour: "24" }, { reminder_lead_minutes: "abc" },
     { quiet_hours: "1", quiet_hours_start: "1325", quiet_hours_end: "420" },
     { quiet_hours: "1", quiet_hours_start: "1320", quiet_hours_end: "" } ].each do |bad|
      patch account_notifications_path, params: { notifications: bad }
      assert_response :unprocessable_content, bad.inspect
    end
    assert_equal [ 30, 6, nil ], @member.reload.then { [ it.reminder_lead_minutes, it.digest_hour, it.quiet_hours_start ] }
  end

  test "quiet hours turn on and off" do
    patch account_notifications_path, params: { notifications: { quiet_hours: "1", quiet_hours_start: "1320", quiet_hours_end: "420" } }
    assert_equal [ 1320, 420 ], @member.reload.then { [ it.quiet_hours_start, it.quiet_hours_end ] }
    patch account_notifications_path, params: { notifications: { quiet_hours: "0", quiet_hours_start: "1320", quiet_hours_end: "420" } }
    assert_not @member.reload.quiet_hours?
  end

  test "without SMTP the email column is disabled and saving leaves stored email choices alone" do
    @member.notification_preferences.create!(category: "pets", push: true, email: true)
    get account_notifications_path
    assert_select "input[type=checkbox][name='notifications[categories][pets][email]'][disabled]"
    assert_select ".matrix-hints", text: /Email isn't set up/

    # Disabled boxes don't submit; even a forged "0" mustn't wipe the choice.
    patch account_notifications_path, params: { notifications: matrix(pets: [ false, false ]) }
    pets = @member.reload.notification_preference("pets")
    assert_not pets.push
    assert pets.email
  end

  test "without a push key the push column is disabled and left alone" do
    smtp_on!
    @member.notification_preferences.create!(category: "pets", push: true, email: false)
    PushKeys.stub_unavailable do
      get account_notifications_path
      assert_select "input[type=checkbox][name='notifications[categories][pets][push]'][disabled]"
      patch account_notifications_path, params: { notifications: matrix(pets: [ false, true ]) }
    end
    pets = @member.reload.notification_preference("pets")
    assert pets.push
    assert pets.email
  end

  test "pause and resume" do
    travel_to Time.zone.local(2026, 11, 23, 9, 0) do
      post pause_account_notifications_path, params: { hours: 8 }
      assert_redirected_to account_notifications_path(anchor: "quiet")
      assert_equal Time.zone.local(2026, 11, 23, 17, 0), @member.reload.notifications_paused_until
      get account_notifications_path
      assert_select "button", text: /Resume now/

      post pause_account_notifications_path, params: { hours: 1000 }
      assert_response :unprocessable_content

      post resume_account_notifications_path
      assert_nil @member.reload.notifications_paused_until
    end
  end
end
