require "test_helper"
require "turbo/broadcastable/test_helper"

class NotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @member = users(:member)
    @admin = users(:admin)
    @smiths = households(:smiths)
  end

  def add_device(user, name = "one")
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    user.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/#{name}",
                                    p256dh: WebPush::Base64Url.encode(browser.public_key.to_octet_string(:uncompressed)),
                                    auth: WebPush::Base64Url.encode(SecureRandom.random_bytes(16)))
  end

  def queued_pushes
    enqueued_jobs.select { |job| job["job_class"] == "SendPushJob" }
  end

  def payload_of(job) = JSON.parse(job["arguments"].second)

  test "toasts open tabs and queues a push per device, named for the household" do
    add_device(@member, "phone")
    add_device(@member, "laptop")
    assert_turbo_stream_broadcasts [@member, :notifications], count: 1 do
      Notifier.notify(@member, category: "assigned", title: "Sam added you to Church", body: "Bring snacks.",
                               path: "/tasks/5", household: @smiths, tag: "task-5-1")
    end
    assert_equal 2, queued_pushes.size
    payload = payload_of(queued_pushes.first)
    assert_equal "The Smiths", payload["title"]
    assert_equal "Sam added you to Church Bring snacks.", payload["body"]
    assert_equal "/tasks/5?household=#{@smiths.id}", payload["path"]
    assert_equal "task-5-1", payload["tag"]
    options = queued_pushes.first["arguments"].last
    assert_equal "normal", options["urgency"]
    assert_equal "task-5-1", options["topic"]
  end

  test "the toast says whether it may buzz, for browsers without push" do
    assert_turbo_stream_broadcasts [@member, :notifications], count: 1 do
      Notifier.notify(@member, category: "pets", title: "Fed Rex", path: "/pets", household: @smiths, tag: "pets")
    end
    assert_includes capture_turbo_stream_broadcasts([@member, :notifications]).last.to_html, 'data-toast-alert-value="true"'

    @member.notification_preferences.create!(category: "pets", push: false)
    @member.notification_preferences.reload
    Notifier.notify(@member, category: "pets", title: "Fed Rex", path: "/pets", household: @smiths, tag: "pets")
    assert_includes capture_turbo_stream_broadcasts([@member, :notifications]).last.to_html, 'data-toast-alert-value="false"'
  end

  test "urgent ones ask the phone to wake" do
    add_device(@member)
    Notifier.notify(@member, category: "assigned", title: "Clash", path: "/tasks", household: @smiths, tag: "t", urgent: true)
    assert_equal "high", queued_pushes.sole["arguments"].last["urgency"]
  end

  test "no devices, no pushes" do
    Notifier.notify(@member, category: "pets", title: "Fed Rex", path: "/pets", household: @smiths, tag: "pets")
    assert_empty queued_pushes
  end

  test "links stay on this site and switch household" do
    assert_equal "/?household=#{@smiths.id}", Notifier.link("https://evil.example/", @smiths)
    assert_equal "/?household=#{@smiths.id}", Notifier.link("//evil.example/", @smiths)
    assert_equal "/tasks?person=2&household=#{@smiths.id}", Notifier.link("/tasks?person=2", @smiths)
    assert_equal "/pets", Notifier.link("/pets", nil)
  end

  test "long tags become valid topics" do
    assert_equal "task-12-3", Notifier.topic("task-12-3")
    assert_match(/\A\h{32}\z/, Notifier.topic("pets-feeding-1-2-3-4-5-6-7-8-9-10-11-12"))
    assert_nil Notifier.topic("")
  end

  test "giving someone a private item pushes its title to them only" do
    add_device(@member)
    add_device(@admin, "admin")
    Current.user = @admin
    task = Task.create!(household: @smiths, title: "Surprise party", private: true, created_by: @admin)
    TaskAssigner.new(task, actor: @admin).assign([@member.id])
    payloads = queued_pushes.map { |job| payload_of(job) }
    assert_equal 1, payloads.size, "the person saving it isn't notified"
    assert_includes payloads.sole["body"], "Surprise party"
    assert_equal "Busy", task.title_for(nil)
  ensure
    Current.reset
  end

  test "status changes reach the others on it, never the person who made them" do
    add_device(@member)
    add_device(@admin, "admin")
    task = Task.create!(household: @smiths, title: "Dishes", assigned_to: @member, created_by: @admin, follow_up: true)
    Current.user = @member
    task.complete!
    bodies = queued_pushes.map { |job| payload_of(job)["body"] }
    assert_equal ["Member User finished Dishes"], bodies
  ensure
    Current.reset
  end

  test "a notification that can't be queued doesn't break the change that caused it" do
    add_device(@member)
    original = Notifier.method(:push_payload)
    Notifier.define_singleton_method(:push_payload) { |*| raise "boom" }
    assert_nothing_raised do
      Notifier.notify(@member, category: "pets", title: "x", path: "/", household: @smiths, tag: "x")
    end
  ensure
    Notifier.define_singleton_method(:push_payload, original)
  end
end
