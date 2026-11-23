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
end
