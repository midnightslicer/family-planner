require "test_helper"

class SendPushJobTest < ActiveJob::TestCase
  setup do
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    @subscription = users(:member).push_subscriptions.create!(
      endpoint: "https://web.push.apple.com/QGuQyavXutnMHk",
      p256dh: WebPush::Base64Url.encode(browser.public_key.to_octet_string(:uncompressed)),
      auth: WebPush::Base64Url.encode(SecureRandom.random_bytes(16)), user_agent: "iPhone Safari/605"
    )
  end

  test "a delivered push marks the device as working" do
    @subscription.update_columns(failed_at: 1.day.ago, last_error: "old")
    FakePushService.new("201").install do |service|
      SendPushJob.perform_now(@subscription.id, "{}", urgency: "normal", topic: "task-1")
      assert_equal 1, service.requests.size
    end
    @subscription.reload
    assert @subscription.last_used_at
    assert_nil @subscription.failed_at
    assert_nil @subscription.last_error
  end

  test "a device the push service says is gone is deleted" do
    %w[404 410].each do |code|
      subscription = @subscription.dup.tap { |s| s.endpoint = "#{@subscription.endpoint}#{code}"; s.save! }
      FakePushService.new(code).install { SendPushJob.perform_now(subscription.id, "{}") }
      assert_not PushSubscription.exists?(subscription.id), code
    end
  end

  test "a busy push service gets two more tries, then the device is marked failing" do
    FakePushService.new("503").install do |service|
      SendPushJob.perform_now(@subscription.id, "{}")
      assert_enqueued_jobs 1, only: SendPushJob
      assert_nil @subscription.reload.failed_at

      2.times { perform_enqueued_jobs(only: SendPushJob) } # each retry queues the next
      assert_equal SendPushJob::ATTEMPTS, service.requests.size
      assert_no_enqueued_jobs only: SendPushJob
    end
    assert @subscription.reload.failing?
    assert_match(/503/, @subscription.last_error)
    assert PushSubscription.exists?(@subscription.id)
  end

  test "a refusal is recorded and not retried" do
    FakePushService.new("400").install { SendPushJob.perform_now(@subscription.id, "{}") }
    assert_no_enqueued_jobs only: SendPushJob
    assert @subscription.reload.failing?
  end

  test "a device removed before the job ran is skipped" do
    @subscription.destroy
    FakePushService.new.install do |service|
      SendPushJob.perform_now(@subscription.id, "{}")
      assert_empty service.requests
    end
  end
end
