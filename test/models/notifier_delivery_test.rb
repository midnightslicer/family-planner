require "test_helper"

class NotifierDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @member = users(:member)
    @smiths = households(:smiths)
    @smiths.update!(time_zone: "Central Time (US & Canada)")
    @member.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/x", **push_keys)
    Setting.set("smtp_host", "smtp.example.com")
  end

  def central(hour, minute = 0) = ActiveSupport::TimeZone["Central Time (US & Canada)"].local(2026, 11, 23, hour, minute)

  def deliver(category: "pets", urgent: false, now: Time.current)
    clear_enqueued_jobs
    Notifier.notify(@member, category: category, title: "Sam fed Rex", path: "/pets", household: @smiths, tag: "pets-1",
                             urgent: urgent, now: now)
    jobs = enqueued_jobs.map { |job| job["job_class"] }
    [ jobs.count("SendPushJob"), jobs.count("ActionMailer::MailDeliveryJob") ]
  end

  def prefer(category, push:, email:)
    @member.notification_preferences.find_or_initialize_by(category: category).update!(push: push, email: email)
    @member.notification_preferences.reset
  end

  test "each category follows the person's push and email choices" do
    prefer("pets", push: true, email: false)
    assert_equal [ 1, 0 ], deliver
    prefer("pets", push: false, email: true)
    assert_equal [ 0, 1 ], deliver
    prefer("pets", push: true, email: true)
    assert_equal [ 1, 1 ], deliver
    prefer("pets", push: false, email: false)
    assert_equal [ 0, 0 ], deliver
  end

  test "defaults apply without a saved row" do
    assert_equal [ 1, 1 ], deliver(category: "assigned")
    assert_equal [ 1, 0 ], deliver(category: "pets")
  end

  test "no email without SMTP" do
    Setting.set("smtp_host", nil)
    assert_equal [ 1, 0 ], deliver(category: "assigned")
  end

  test "a pause stops pushes, urgent ones too, but not email" do
    @member.update!(notifications_paused_until: 1.hour.from_now)
    assert_equal [ 0, 1 ], deliver(category: "assigned")
    assert_equal [ 0, 1 ], deliver(category: "assigned", urgent: true)
    @member.update!(notifications_paused_until: 1.minute.ago)
    assert_equal [ 1, 1 ], deliver(category: "assigned")
  end

  test "quiet hours across midnight, on the household's clock, with both edges" do
    @member.update!(quiet_hours_start: 22 * 60, quiet_hours_end: 7 * 60)
    assert_equal [ 1, 0 ], deliver(now: central(21, 59))
    assert_equal [ 0, 0 ], deliver(now: central(22, 0))
    assert_equal [ 0, 0 ], deliver(now: central(3, 0))
    assert_equal [ 0, 0 ], deliver(now: central(6, 59))
    assert_equal [ 1, 0 ], deliver(now: central(7, 0))
    # 23:00 in London is 17:00 in Chicago: not quiet there.
    assert_equal [ 1, 0 ], deliver(now: ActiveSupport::TimeZone["London"].local(2026, 11, 23, 23))
  end

  test "daytime quiet hours" do
    @member.update!(quiet_hours_start: 13 * 60, quiet_hours_end: 14 * 60 + 30)
    assert_equal [ 1, 0 ], deliver(now: central(12, 59))
    assert_equal [ 0, 0 ], deliver(now: central(14, 29))
    assert_equal [ 1, 0 ], deliver(now: central(14, 30))
  end

  test "urgent requests get through quiet hours; email ignores them" do
    @member.update!(quiet_hours_start: 22 * 60, quiet_hours_end: 7 * 60)
    assert_equal [ 1, 1 ], deliver(category: "assigned", urgent: true, now: central(23))
    assert_equal [ 0, 1 ], deliver(category: "assigned", now: central(23))
  end

  test "an unknown category is a programming error" do
    assert_raises(ArgumentError) { deliver(category: "gossip") }
  end
end
