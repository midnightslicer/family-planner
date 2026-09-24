module Admin
  class SettingsController < BaseController
    KEYS = %w[app_name app_url smtp_host smtp_port smtp_user smtp_from].freeze

    def show
      @settings = KEYS.index_with { |key| Setting.get(key) }
      @password_saved = Setting.get("smtp_password").present?
      @smtp_tls = Setting.get("smtp_tls") == "true"
    end

    def update
      values = params.fetch(:settings, {})
      KEYS.each { |key| Setting.set(key, values[key].to_s.strip.presence) }
      Setting.set("smtp_tls", values[:smtp_tls] == "1" ? "true" : nil)
      # The saved password is never sent back to the browser; a blank field
      # keeps it, and the checkbox clears it.
      if values[:clear_smtp_password] == "1"
        Setting.set("smtp_password", nil)
      elsif values[:smtp_password].present?
        Setting.set("smtp_password", values[:smtp_password])
      end
      redirect_to admin_settings_path, notice: "Settings saved."
    end

    # Sends synchronously so a wrong host or password shows up right here.
    def test_email
      SetupMailer.test_email(current_user.email).deliver_now
      redirect_to admin_settings_path, notice: "Test email sent to #{current_user.email}."
    rescue StandardError => error
      redirect_to admin_settings_path, alert: "The test email failed: #{error.message.truncate(200)}"
    end
  end
end
