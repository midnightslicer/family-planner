# Configures ActionMailer from database-backed Settings when available,
# falling back to ENV for environments where the table does not exist yet
# (fresh boots, migrations pending, asset precompile in Docker builds).
Rails.application.config.to_prepare do
  mail_settings =
    begin
      if ActiveRecord::Base.connection.table_exists?(:settings)
        {
          app_name: Setting.get("app_name"),
          host: Setting.get("smtp_host"),
          port: Setting.get("smtp_port"),
          user: Setting.get("smtp_user"),
          password: Setting.get("smtp_password"),
          from: Setting.get("smtp_from"),
          tls: Setting.get("smtp_tls")
        }
      end
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      nil
    end

  mail_settings ||= {
    app_name: ENV["APP_NAME"],
    host: ENV["SMTP_HOST"],
    port: ENV["SMTP_PORT"],
    user: ENV["SMTP_USER"],
    password: ENV["SMTP_PASSWORD"],
    from: ENV["SMTP_FROM"],
    tls: ENV["SMTP_TLS"]
  }

  smtp_settings = {}
  if mail_settings[:host].present?
    smtp_settings[:address] = mail_settings[:host]
    smtp_settings[:port] = (mail_settings[:port].presence || 587).to_i
    smtp_settings[:domain] = mail_settings[:host]
    smtp_settings[:user_name] = mail_settings[:user] if mail_settings[:user].present?
    smtp_settings[:password] = mail_settings[:password] if mail_settings[:password].present?
    smtp_settings[:enable_starttls_auto] = true
    smtp_settings[:openssl_verify_mode] = "none" if Rails.env.development? && mail_settings[:tls] != "true"
    smtp_settings[:authentication] = :plain if mail_settings[:user].present?
  end

  ActionMailer::Base.smtp_settings = smtp_settings if smtp_settings.present?

  default_from = mail_settings[:from].presence || ENV["SMTP_FROM"] || "family-status@localhost"
  ActionMailer::Base.default from: default_from
end