module Admin
  class SettingsController < BaseController
    SETTINGS_KEYS = %w[app_name smtp_host smtp_port smtp_user smtp_password smtp_from smtp_tls].freeze

    def show
      @settings = SETTINGS_KEYS.index_with { |key| Setting.get(key) }
    end

    def update
      SETTINGS_KEYS.each { |key| Setting.set(key, params.dig(:settings, key).presence) }
      redirect_to admin_settings_path, notice: "Settings saved."
    end

    def test_email
      if Setting.get("smtp_host").present?
        SetupMailer.test_email.deliver_later
        redirect_to admin_settings_path, notice: "Test email sent."
      else
        redirect_to admin_settings_path, alert: "SMTP is not configured — fill in the SMTP fields first."
      end
    end
  end
end