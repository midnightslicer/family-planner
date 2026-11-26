module NotificationsHelper
  # data-* for the element the push controller (push_controller.js) runs on:
  # the endpoints it calls, and digests of the devices the server knows.
  def push_controller_data(devices)
    {
      controller: "push",
      push_subscribe_url_value: push_subscriptions_path,
      push_unsubscribe_url_value: unsubscribe_push_subscriptions_path,
      push_test_url_value: test_push_subscriptions_path,
      push_known_value: devices.map(&:endpoint_digest).to_json
    }
  end

  def reminder_lead_options(selected)
    options = User::REMINDER_LEADS.map { |minutes| [ minutes == 60 ? "1 hour before" : "#{minutes} minutes before", minutes ] }
    options_for_select(options, selected)
  end

  def digest_hour_options(selected)
    options_for_select(User::DIGEST_HOURS.map { |hour| [ "at #{clock_label(hour * 60)}", hour ] }, selected)
  end

  # Every half hour of the day, for quiet hours (minutes after midnight).
  def quiet_hours_options(selected)
    options_for_select((0...24 * 60).step(User::QUIET_STEP).map { |minute| [ clock_label(minute), minute ] }, selected)
  end

  # 0 -> "12:00 AM", 1290 -> "9:30 PM" (the app's clock style elsewhere).
  def clock_label(minute)
    Time.utc(2000, 1, 1, minute / 60, minute % 60).strftime("%-l:%M %p")
  end

  # "6:30 PM" today, or "Tue 9:00 AM" on another day.
  def paused_until_text(time)
    time = time.in_time_zone
    time.to_date == Date.current ? time.strftime("%-l:%M %p") : time.strftime("%a %-l:%M %p")
  end
end
