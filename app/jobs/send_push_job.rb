# Delivers one push to one device (PushSubscription#deliver). Queued by
# Notifier so a slow or unreachable push service never holds up a request.
#
# A push service that's busy or unreachable (429, 5xx, timeouts) gets two
# more tries with backoff; then the device is marked as failing. A device
# the service says is gone (404/410) is deleted.
class SendPushJob < ApplicationJob
  queue_as :background

  class PushServiceBusy < StandardError; end

  ATTEMPTS = 3

  retry_on PushServiceBusy, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    PushSubscription.find_by(id: job.arguments.first)&.record_failure!(error.message)
  end

  def perform(subscription_id, payload, ttl: 12.hours.to_i, urgency: "normal", topic: nil)
    subscription = PushSubscription.find_by(id: subscription_id) or return # removed meanwhile

    result = subscription.deliver(payload, ttl: ttl, urgency: urgency, topic: topic)
    raise PushServiceBusy, result.message if result.retry?
  end
end
