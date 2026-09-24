# Instance-wide configuration, read from the settings table with environment
# variables as a fallback, so a server can be configured either from the
# admin screens or entirely from its env (handy for Kamal and Compose).
module AppSettings
  DEFAULT_APP_NAME = "Family Status".freeze
  SMTP_KEYS = %w[smtp_host smtp_port smtp_user smtp_password smtp_from smtp_tls].freeze

  module_function

  def app_name
    Setting.get("app_name").presence || ENV["APP_NAME"].presence || DEFAULT_APP_NAME
  end

  # The public base URL used in emails, e.g. "https://status.example.com".
  def app_url
    ENV["APP_URL"].presence || Setting.get("app_url").presence
  end

  def url_options
    uri = URI.parse(app_url.to_s)
    return {} unless uri.host

    options = { protocol: uri.scheme, host: uri.host }
    options[:port] = uri.port unless uri.port == uri.default_port
    options
  rescue URI::InvalidURIError
    {}
  end

  def smtp_configured?
    value("smtp_host").present?
  end

  # Settings for Mail::SMTP, or nil when email isn't set up.
  def smtp_settings
    host = value("smtp_host")
    return nil if host.blank?

    port = (value("smtp_port").presence || 587).to_i
    implicit_tls = ActiveModel::Type::Boolean.new.cast(value("smtp_tls")) || port == 465
    settings = { address: host, port: port, open_timeout: 10, read_timeout: 15 }
    if implicit_tls
      settings[:tls] = true
    else
      settings[:enable_starttls_auto] = true
    end

    user = value("smtp_user")
    if user.present?
      settings.merge!(user_name: user, password: value("smtp_password"), authentication: :plain)
    end
    settings
  end

  def mail_from
    value("smtp_from").presence || "#{app_name.delete('<>"')} <no-reply@#{url_options[:host] || 'localhost'}>"
  end

  # A setting saved in the admin screens wins over its SMTP_* env var.
  def value(key)
    Setting.get(key).presence || ENV[key.upcase].presence
  end

  # Four groups of four from an HMAC of the secret key base: stable across
  # restarts, different on every install, and only useful until the first
  # account exists. Printed to the server log at boot (see
  # config/initializers/setup_code.rb) and by `bin/rails setup:code`.
  def setup_code
    digest = OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "family-status setup code")
    Totp.base32_encode(digest)[0, 16].downcase.scan(/.{4}/).join("-")
  end

  def setup_code_required?
    !Rails.env.development?
  end

  def valid_setup_code?(code)
    normalized = code.to_s.downcase.gsub(/[^a-z2-7]/, "")
    ActiveSupport::SecurityUtils.secure_compare(normalized, setup_code.delete("-"))
  end
end
