require "test_helper"

class ReminderJobTest < ActiveJob::TestCase
  ZONE = "Central Time (US & Canada)".freeze

  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
    @smiths.update!(time_zone: ZONE)
  end

  def at(*args) = ActiveSupport::TimeZone[ZONE].local(*args)

  def event(starts_at, title: "Church", people: [ @member ], status: "accepted", **attributes)
    Task.create!(household: @smiths, title: title, starts_at: starts_at, ends_at: starts_at + 1.hour, **attributes).tap do |task|
      people.each { |person| task.assignments.create!(user: person, status: status) }
    end
  end

  # [[recipient, title, body]] for everything Notifier was asked to send.
  def sent
    calls = []
    original = Notifier.method(:notify)
    Notifier.define_singleton_method(:notify) do |user, **options|
      calls << [ user, options[:title], options[:body], options[:category], options[:ttl] ]
      original.call(user, **options)
    end
    yield
    calls
  ensure
    Notifier.define_singleton_method(:notify, original)
  end

  test "an accepted event is announced exactly its lead time before, once" do
    church = event(at(2026, 11, 29, 10, 0))
    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 44)) })

    calls = sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 45)) }
    assert_equal 1, calls.size
    user, title, body, category, ttl = calls.sole
    assert_equal @member, user
    assert_equal "Church at 10:00 AM", title
    assert_equal "Starts in 15 minutes", body
    assert_equal "event_reminders", category
    assert_equal 15 * 60, ttl

    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 45)) }, "same tick twice")
    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 50)) }, "a later tick")
    assert_equal 1, ReminderSent.where(task: church).count
  end

  test "each person's own lead time, and the place" do
    @admin.update!(reminder_lead_minutes: 60)
    event(at(2026, 11, 29, 10, 0), people: [ @member, @admin ], place: "Grace Church")
    early = sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 0)) }
    assert_equal [ [ @admin, "Starts in 1 hour · Grace Church" ] ], early.map { |c| [ c[0], c[2] ] }
    later = sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 45)) }
    assert_equal [ @member ], later.map(&:first)
  end

  test "a missed tick still reminds before the start, never after" do
    event(at(2026, 11, 29, 10, 0))
    assert_equal 1, sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 52)) }.size
    other = event(at(2026, 11, 29, 11, 0), title: "Lunch")
    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 11, 0)) })
    assert_not ReminderSent.exists?(task: other)
  end

  test "changing the lead time afterwards doesn't repeat a reminder" do
    event(at(2026, 11, 29, 10, 0))
    sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 45)) }
    @member.update!(reminder_lead_minutes: 5)
    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 55)) })
  end

  test "pending, declined and anyone's events get nothing; finished ones neither" do
    event(at(2026, 11, 29, 10, 0), status: "pending")
    event(at(2026, 11, 29, 10, 0), title: "Said no", status: "declined")
    event(at(2026, 11, 29, 10, 0), title: "Anyone", people: [])
    event(at(2026, 11, 29, 10, 0), title: "Done early", status: "accepted").update!(status: :completed)
    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 50)) })
  end

  test "each occurrence of a recurring event gets its own reminder" do
    church = event(at(2026, 11, 29, 10, 0), recurrence_interval: "weekly", created_by: @member)
    assert_equal 1, sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 45)) }.size
    church.roll_forward!(at(2026, 11, 29, 11, 30))
    next_week = Task.where(title: "Church").where.not(id: church.id).sole
    assert_equal at(2026, 12, 6, 10, 0), next_week.starts_at
    assert_equal [ @member ], sent { ReminderJob.perform_now(at(2026, 12, 6, 9, 45)) }.map(&:first)
  end

  test "a retimed event is reminded again at its new time" do
    task = event(at(2026, 11, 29, 10, 0))
    sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 45)) }
    task.update!(starts_at: at(2026, 11, 29, 11, 0), ends_at: at(2026, 11, 29, 12, 0))
    assert_equal 1, sent { ReminderJob.perform_now(at(2026, 11, 29, 10, 45)) }.size
  end

  test "private events are only reminded to their own people, with their title" do
    event(at(2026, 11, 29, 10, 0), title: "Surprise party", private: true, created_by: @admin)
    calls = sent { ReminderJob.perform_now(at(2026, 11, 29, 9, 45)) }
    assert_equal [ [ @member, "Surprise party at 10:00 AM" ] ], calls.map { |c| c[0, 2] }
  end

  test "times are on the household's clock across a DST change" do
    # US clocks go back at 2:00 AM on Nov 1, 2026: 9:00 AM that day is UTC-6.
    event(at(2026, 11, 1, 9, 0))
    calls = sent { ReminderJob.perform_now(Time.utc(2026, 11, 1, 14, 45)) }
    assert_equal "Church at 9:00 AM", calls.sole[1]
  end

  test "the to-do digest goes out once, in the chosen hour, on the household's clock" do
    @member.notification_preferences.create!(category: "todo_digest", push: true, email: false)
    Task.create!(household: @smiths, title: "Pay rent", assigned_to: @member, due_on: Date.new(2026, 11, 29))
    Task.create!(household: @smiths, title: "Call vet", assigned_to: @member, due_on: Date.new(2026, 11, 29))
    Task.create!(household: @smiths, title: "Tomorrow", assigned_to: @member, due_on: Date.new(2026, 11, 30))
    Task.create!(household: @smiths, title: "Done", assigned_to: @member, due_on: Date.new(2026, 11, 29), status: :completed)

    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 6, 59)) })
    calls = sent { ReminderJob.perform_now(at(2026, 11, 29, 7, 0)) }
    assert_equal [ [ @member, "2 to-dos for today", "Pay rent and Call vet", "todo_digest" ] ], calls.map { |c| c[0, 4] }
    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 7, 1)) })
    # 7:00 UTC is 1:00 AM in Chicago: not the hour.
    assert_empty(sent { ReminderJob.perform_now(Time.utc(2026, 11, 30, 7, 0)) })
  end

  test "no digest when nothing's due, or when the person wants neither push nor email" do
    @member.notification_preferences.create!(category: "todo_digest", push: true, email: false)
    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 29, 7, 0)) })

    Task.create!(household: @smiths, title: "Pay rent", assigned_to: @member, due_on: Date.new(2026, 11, 30))
    @member.notification_preferences.find_by!(category: "todo_digest").update!(push: false)
    assert_empty(sent { ReminderJob.perform_now(at(2026, 11, 30, 7, 0)) })
  end
end
