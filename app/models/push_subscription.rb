# A browser (phone, laptop) that agreed to receive push notifications for
# someone. The endpoint is a URL on the browser vendor's push service; it is
# only ever posted to if it's on WebPush::ALLOWED_HOSTS, checked here when
# it's saved and again by WebPush::Client when it's used.
class PushSubscription < ApplicationRecord
  belongs_to :user

  encrypts :p256dh, :auth

  # Tests swap in a fake HTTP transport for WebPush::Client.
  class_attribute :transport, default: nil

  validates :endpoint, presence: true, length: { maximum: 2048 }, uniqueness: true
  validates :user_agent, length: { maximum: 500 }
  validate :endpoint_on_a_push_service
  validate :keys_usable

  def device_name
    Passkey.name_from_user_agent(user_agent, fallback: "Browser")
  end

  def failing?
    failed_at.present?
  end

  def p256dh_bytes = WebPush::Base64Url.decode(p256dh)
  def auth_bytes = WebPush::Base64Url.decode(auth)

  # Sends one push now and records how it went: a subscription the push
  # service says is gone is deleted; a refusal is noted for the device list.
  # Returns the WebPush::Client::Result (status :retry is left to the caller).
  def deliver(payload, ttl: 12.hours.to_i, urgency: "normal", topic: nil)
    vapid = PushKeys.vapid
    return record(WebPush::Client::Result.new(status: :failed, message: "Push isn't set up on this server")) unless vapid

    result = WebPush::Client.new(vapid, transport: transport)
                            .deliver(endpoint: endpoint, p256dh: p256dh_bytes, auth: auth_bytes, payload: payload,
                                     ttl: ttl, urgency: urgency, topic: topic)
    record(result)
  rescue WebPush::Error, ActiveRecord::Encryption::Errors::Base => error
    record(WebPush::Client::Result.new(status: :failed, message: error.message))
  end

  def record_failure!(message)
    update_columns(last_error: message.to_s.truncate(250), failed_at: Time.current) if persisted?
  end

  private

  def record(result)
    case result.status
    when :ok then update_columns(last_used_at: Time.current, last_error: nil, failed_at: nil)
    when :gone then destroy
    when :failed then record_failure!(result.message)
    end
    result
  end

  def endpoint_on_a_push_service
    errors.add(:endpoint, "isn't a known push service") if endpoint.present? && !WebPush.allowed_endpoint?(endpoint)
  end

  def keys_usable
    WebPush::Encryption.point(p256dh_bytes)
    errors.add(:auth, "is invalid") unless auth_bytes.bytesize == 16
  rescue WebPush::Error
    errors.add(:base, "The browser's push keys are invalid")
  end
end
