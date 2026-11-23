# Devices (browsers) that get push notifications for the signed-in person.
# Always scoped to current_user: nobody can see or touch another person's
# devices, admins included.
class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!, except: :renew
  # The service worker has no CSRF token. `renew` doesn't act on the session
  # at all: knowing the old endpoint, a secret only that browser and we
  # hold, is what authorises it.
  skip_forgery_protection only: :renew
  rate_limit to: 20, within: 1.minute, only: [:create, :test, :unsubscribe, :renew], with: -> { rate_limited_json }

  # POST /push_subscriptions (JSON: { subscription: PushSubscription.toJSON() })
  #
  # Upserts by endpoint. An endpoint already saved for someone else moves to
  # whoever is signed in now: a shared phone, a new sign-in, so the last
  # person to sign in on a device is the one it notifies.
  def create
    data = params.require(:subscription)
    keys = data[:keys].respond_to?(:[]) ? data[:keys] : {}
    subscription = PushSubscription.find_or_initialize_by(endpoint: data[:endpoint].to_s)
    subscription.assign_attributes(user: current_user, p256dh: keys[:p256dh].to_s, auth: keys[:auth].to_s,
                                   user_agent: request.user_agent.to_s.first(500), last_error: nil, failed_at: nil)
    if subscription.save
      render json: { id: subscription.id, device: subscription.device_name }, status: :created
    else
      render_json_error(subscription.errors.full_messages.to_sentence)
    end
  rescue ActionController::ParameterMissing
    render_json_error("Missing subscription.")
  end

  # POST /push_subscriptions/renew (JSON: { old_endpoint, subscription }),
  # from the service worker's pushsubscriptionchange: the same device, for
  # the same person, at a new endpoint.
  def renew
    subscription = PushSubscription.find_by(endpoint: params[:old_endpoint].to_s) or return head(:not_found)
    data = params.require(:subscription)
    keys = data[:keys].respond_to?(:[]) ? data[:keys] : {}
    PushSubscription.where(endpoint: data[:endpoint].to_s).where.not(id: subscription.id).delete_all
    if subscription.update(endpoint: data[:endpoint].to_s, p256dh: keys[:p256dh].to_s, auth: keys[:auth].to_s, last_error: nil, failed_at: nil)
      head :no_content
    else
      render_json_error(subscription.errors.full_messages.to_sentence)
    end
  rescue ActionController::ParameterMissing
    render_json_error("Missing subscription.")
  end

  # POST /push_subscriptions/unsubscribe (JSON: { endpoint }): this device
  # turned notifications off.
  def unsubscribe
    current_user.push_subscriptions.where(endpoint: params[:endpoint].to_s).destroy_all
    head :no_content
  end

  # DELETE /push_subscriptions/:id: "Remove" in the device list.
  def destroy
    subscription = current_user.push_subscriptions.find_by(id: params[:id]) or return head(:not_found)
    subscription.destroy
    redirect_back_or_to account_root_path, notice: "Removed #{subscription.device_name}. It won't get notifications any more.",
                                           status: :see_other, allow_other_host: false
  end

  # POST /push_subscriptions/test (JSON: { endpoint }, or none for every
  # device). Sends right away, not through the queue, so the button can say
  # whether it worked.
  def test
    subscriptions = current_user.push_subscriptions
    subscriptions = subscriptions.where(endpoint: params[:endpoint].to_s) if params[:endpoint].present?
    subscriptions = subscriptions.to_a
    return render_json_error("This device isn't set up for notifications yet.", status: :not_found) if subscriptions.empty?

    payload = Notifier.push_payload(Notifier::Note.new(
      title: "Notifications are working on this device.", path: Notifier.link("/", current_household),
      household: current_household, tag: "test"
    ))
    results = subscriptions.map { |subscription| subscription.deliver(payload, ttl: 300, urgency: "high") }
    failed = results.reject(&:ok?)
    if failed.empty?
      render json: { sent: results.size }
    elsif failed.first.gone?
      render_json_error("This device's subscription had expired, so it's been removed. Turn notifications on again.", status: :gone)
    else
      render_json_error("The push service refused it: #{failed.first.message}".truncate(200), status: :bad_gateway)
    end
  end
end
