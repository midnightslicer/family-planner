require "test_helper"

class PushSubscriptionsTest < ActionDispatch::IntegrationTest
  ENDPOINT = "https://fcm.googleapis.com/fcm/send/device-one".freeze

  setup do
    @member = users(:member)
    @admin = users(:admin)
    @browser = OpenSSL::PKey::EC.generate("prime256v1")
  end

  def browser_subscription(endpoint = ENDPOINT, key: @browser)
    { endpoint: endpoint, expirationTime: nil, keys: push_keys(key) }
  end

  def subscribe(subscription = browser_subscription, user_agent: "Mozilla/5.0 (Linux; Android 14) Chrome/131.0 Mobile")
    post push_subscriptions_path, params: { subscription: subscription }, as: :json, headers: { "User-Agent" => user_agent }
  end

  test "signed out, nothing is saved" do
    subscribe
    assert_response :unauthorized
    assert_equal 0, PushSubscription.count
  end

  test "a browser subscribes, and its keys are stored encrypted" do
    sign_in @member
    subscribe
    assert_response :created
    assert_equal "Android · Chrome", response.parsed_body["device"]

    subscription = @member.push_subscriptions.sole
    assert_equal ENDPOINT, subscription.endpoint
    assert_equal 65, subscription.p256dh_bytes.bytesize
    raw = PushSubscription.connection.select_value("SELECT p256dh FROM push_subscriptions WHERE id = #{subscription.id}")
    assert_not_includes raw, subscription.p256dh
  end

  test "endpoints off the push-service allowlist, or over http, are refused" do
    sign_in @member
    ["http://fcm.googleapis.com/fcm/send/x", "https://127.0.0.1/x", "https://evil.example/push", "https://169.254.169.254/"].each do |endpoint|
      subscribe(browser_subscription(endpoint))
      assert_response :unprocessable_content, endpoint
    end
    assert_equal 0, PushSubscription.count
  end

  test "broken keys are refused" do
    sign_in @member
    subscribe(browser_subscription.merge(keys: { p256dh: "AAAA", auth: "AAAA" }))
    assert_response :unprocessable_content
    subscribe(browser_subscription.except(:keys))
    assert_response :unprocessable_content
    post push_subscriptions_path, params: {}, as: :json
    assert_response :unprocessable_content
    assert_equal 0, PushSubscription.count
  end

  test "subscribing again updates the same row, moving the device to whoever signs in on it next" do
    sign_in @member
    subscribe
    subscribe
    assert_equal 1, PushSubscription.count
    sign_out @member
    sign_in @admin
    subscribe
    assert_equal [], @member.push_subscriptions.reload.to_a
    assert_equal ENDPOINT, @admin.push_subscriptions.sole.endpoint
  end

  test "people can only remove their own devices" do
    sign_in @member
    subscribe
    mine = @member.push_subscriptions.sole
    sign_out @member

    sign_in @admin
    delete push_subscription_path(mine)
    assert_response :not_found
    post unsubscribe_push_subscriptions_path, params: { endpoint: ENDPOINT }, as: :json
    assert PushSubscription.exists?(mine.id)
    sign_out @admin

    sign_in @member
    delete push_subscription_path(mine)
    assert_response :see_other
    assert_not PushSubscription.exists?(mine.id)
  end

  test "turning notifications off on a device forgets it" do
    sign_in @member
    subscribe
    post unsubscribe_push_subscriptions_path, params: { endpoint: ENDPOINT }, as: :json
    assert_response :no_content
    assert_equal 0, PushSubscription.count
  end

  test "a test push goes to this device right away and says whether it worked" do
    sign_in @member
    subscribe
    FakePushService.new.install do |service|
      post test_push_subscriptions_path, params: { endpoint: ENDPOINT }, as: :json
      assert_response :success
      assert_equal 1, response.parsed_body["sent"]
      uri, request = service.requests.sole
      assert_equal ENDPOINT, uri.to_s
      assert_equal "high", request["Urgency"]

      service.respond_with("403")
      post test_push_subscriptions_path, params: { endpoint: ENDPOINT }, as: :json
      assert_response :bad_gateway
      assert_match(/refused/, response.parsed_body["error"])
      assert @member.push_subscriptions.sole.failing?
    end
  end

  test "a test push to a device the push service has forgotten removes it and says so" do
    sign_in @member
    subscribe
    FakePushService.new("410").install do
      post test_push_subscriptions_path, params: { endpoint: ENDPOINT }, as: :json
    end
    assert_response :gone
    assert_match(/expired/, response.parsed_body["error"])
    assert_equal 0, @member.push_subscriptions.count
  end

  test "a test push for a device that isn't subscribed says so" do
    sign_in @member
    post test_push_subscriptions_path, params: { endpoint: ENDPOINT }, as: :json
    assert_response :not_found
  end
end
