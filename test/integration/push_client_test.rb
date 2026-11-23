require "test_helper"
require "turbo/broadcastable/test_helper"

class PushClientTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  OLD = "https://updates.push.services.mozilla.com/wpush/v2/old".freeze
  NEW = "https://updates.push.services.mozilla.com/wpush/v2/new".freeze

  setup do
    @member = users(:member)
  end

  def keys
    browser = OpenSSL::PKey::EC.generate("prime256v1")
    { p256dh: WebPush::Base64Url.encode(browser.public_key.to_octet_string(:uncompressed)),
      auth: WebPush::Base64Url.encode(SecureRandom.random_bytes(16)) }
  end

  def device(endpoint = OLD, user: @member)
    user.push_subscriptions.create!(endpoint: endpoint, **keys, user_agent: "Mozilla/5.0 (Android 14) Firefox/133.0")
  end

  test "the service worker moves a replaced subscription to its new endpoint, no session needed" do
    old = device
    post renew_push_subscriptions_path, params: { old_endpoint: OLD, subscription: { endpoint: NEW, keys: keys } }, as: :json
    assert_response :no_content
    assert_equal NEW, old.reload.endpoint
    assert_equal @member, old.user
  end

  test "renewing needs the old endpoint, and the new one must be a push service" do
    post renew_push_subscriptions_path, params: { old_endpoint: "https://fcm.googleapis.com/fcm/send/guess", subscription: { endpoint: NEW, keys: keys } }, as: :json
    assert_response :not_found

    old = device
    post renew_push_subscriptions_path, params: { old_endpoint: OLD, subscription: { endpoint: "https://evil.example/x", keys: keys } }, as: :json
    assert_response :unprocessable_content
    assert_equal OLD, old.reload.endpoint
  end

  test "the Notifications page shows this device's panel and the device list, from the menu" do
    device
    sign_in @member
    get dashboard_path
    assert_select ".user-menu-panel a[href=?]", account_notifications_path
    get account_notifications_path
    assert_response :success
    assert_select "[data-controller=push][data-push-known-value*=?]", Digest::SHA256.hexdigest(OLD)
    assert_select "[data-push-target=state]", 7
    assert_select "[data-state=local] button[data-action='push#testLocal']"
    assert_select "tr[data-push-target=device][data-digest=?]", Digest::SHA256.hexdigest(OLD), text: /Android · Firefox/
    assert_select "button[data-action='push#enable']"
  end

  test "the Notifications page needs sign-in" do
    get account_notifications_path
    assert_redirected_to new_user_session_path
  end

  test "a failing device says so" do
    device.update!(failed_at: Time.current, last_error: "403 Forbidden")
    sign_in @member
    get account_notifications_path
    assert_select ".status-chip[title='403 Forbidden']", text: /Last one failed/
  end

  test "signed-in pages carry the push key and whose device it is; signed-out ones don't" do
    get new_user_session_path
    assert_select "meta[name=push-key]", 0
    sign_in @member
    get dashboard_path
    assert_select "meta[name=push-key][content=?]", PushKeys.public_key
    assert_select "meta[name=push-user][content=?]", @member.id.to_s
    assert_select "[data-controller=push-sync][data-push-sync-url-value=?]", push_subscriptions_path
    assert_select "#notifications.toast-stack"
  end

  test "the dashboard nudge links to the settings and starts hidden" do
    sign_in @member
    get dashboard_path
    assert_select ".invite-banner[data-controller=push-nudge][hidden]" do
      assert_select "a[href=?]", account_notifications_path
    end
  end

  test "an update arrives in open tabs as a toast that links to it" do
    task = Task.create!(household: households(:smiths), title: "Bins", assigned_to: @member)
    html = ApplicationController.render(partial: "shared/notification",
                                        locals: { title: "The Smiths", body: "Sam <b>finished</b> Bins", tag: "task-1", path: "/tasks/#{task.id}?household=1" })
    fragment = Nokogiri::HTML5.fragment(html)
    toast = fragment.at_css(".toast[data-controller=toast]")
    assert toast
    assert_equal "Sam <b>finished</b> Bins", toast.at_css(".toast-body span").text, "user text is escaped"
    assert_equal "/tasks/#{task.id}?household=1", toast.at_css("a")["href"]
  end
end
