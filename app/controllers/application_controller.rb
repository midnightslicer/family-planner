class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp, web push, badges, import maps,
  # CSS nesting, and CSS :has. The wall skips this: an older wall-mounted
  # tablet should still be able to show the board.
  allow_browser versions: :modern, unless: :kiosk?

  before_action :require_setup
  before_action :set_current_context
  before_action :switch_household_from_link
  around_action :use_household_time_zone
  # Person cards changed by this request re-render once each, at the end.
  around_action :batch_card_broadcasts

  helper_method :current_household, :app_name

  private

  def kiosk?
    false
  end

  # First-run gate: until the first account exists, every page leads to the
  # setup wizard.
  def require_setup
    redirect_to setup_path unless User.exists?
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
    redirect_to setup_path
  end

  def set_current_context
    Current.user = current_user
    return unless current_user

    household = current_user.households.find_by(id: session[:current_household_id]) if session[:current_household_id]
    Current.household = household || current_user.households.order(:id).first
    session[:current_household_id] = Current.household&.id
  end

  def current_household
    Current.household
  end

  # Notification links carry ?household=<id> (Notifier.link), so tapping one
  # opens the household it's about. Only one of the person's own households
  # is switched to; any other id is ignored. Either way the page reloads at
  # its clean address. Signed out, the param rides along to after sign-in.
  def switch_household_from_link
    id = params[:household]
    return unless id.is_a?(String) && request.get? && Current.user

    household = Current.user.households.find_by(id: id)
    if household
      session[:current_household_id] = household.id
      Current.household = household
    end
    return unless request.format.html?

    # Squeezed: "//tasks" routes to /tasks, but as a Location it would be
    # protocol-relative, i.e. another site.
    path = request.path.squeeze("/")
    query = request.query_parameters.except("household")
    redirect_to(query.empty? ? path : "#{path}?#{query.to_query}")
  end

  # Every request runs on the household's clock (set by an admin): work
  # hours, "today", "fed today", and every time shown, so the whole family
  # sees the same thing wherever their phones are. Until one is set, the
  # browser's own zone (a `tz` cookie from application.js), then the app
  # default.
  def use_household_time_zone(&)
    Time.use_zone(time_zone_household&.zone || browser_time_zone || Time.zone_default, &)
  end

  def batch_card_broadcasts(&)
    Household.batching_cards(&)
  end

  # Whose clock this request runs on. The wall overrides it (the slug picks the household).
  def time_zone_household
    current_household
  end

  def browser_time_zone
    ActiveSupport::TimeZone[cookies[:tz].to_s] if cookies[:tz].present?
  rescue ArgumentError, TZInfo::InvalidTimezoneIdentifier
    nil
  end

  def app_name
    AppSettings.app_name
  end

  def require_household!
    not_found unless current_household
  end

  # Not there, or not yours to see: the 404 page (public/404.html) for a
  # browser, a bare 404 for anything else (fetch, Turbo Stream, JSON).
  def not_found
    if request.format == :html # not html?, which a Turbo Stream request also passes
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false, content_type: "text/html"
    else
      head :not_found
    end
  end

  def require_admin!
    head :forbidden unless current_user&.admin?
  end

  # Passkey ceremonies: the relying party is whatever origin the person is
  # actually on, which is also what their browser will bind the passkey to.
  def relying_party
    WebAuthn::RelyingParty.new(id: request.host, origin: request.base_url, name: app_name)
  end

  # Ceremony state lives in the session for a few minutes: the challenge the
  # browser must sign, plus anything else the ceremony needs.
  CEREMONY_TTL = 5.minutes

  def start_ceremony(key, **data)
    challenge = WebAuthn::RelyingParty.challenge
    session[key] = data.transform_keys(&:to_s).merge("challenge" => challenge, "at" => Time.current.to_i)
    challenge
  end

  def finish_ceremony(key)
    state = session.delete(key)
    raise WebAuthn::Error, "passkey request expired; please try again" unless state.is_a?(Hash) &&
      Time.at(state["at"].to_i) > CEREMONY_TTL.ago
    state
  end

  # The credential arrives either as a JSON body field or, from a regular
  # form post, as a JSON string in a hidden field.
  def credential_param(key = :credential)
    value = params[key]
    credential =
      if value.is_a?(String) then JSON.parse(value)
      elsif value.respond_to?(:to_unsafe_h) then value.to_unsafe_h
      end
    raise WebAuthn::Error, "missing passkey response" unless credential.is_a?(Hash)

    credential
  rescue JSON::ParserError
    raise WebAuthn::Error, "malformed passkey response"
  end

  def render_json_error(message, status: :unprocessable_content)
    render json: { error: message }, status: status
  end

  def rate_limited_json
    render_json_error("Too many attempts. Wait a minute and try again.", status: :too_many_requests)
  end
end
