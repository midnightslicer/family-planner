# Mail settings are read when a message is sent, not at boot, so SMTP details
# saved in Admin -> Settings (or the SMTP_* env fallbacks) apply immediately.
# See AppSettings for where each value comes from.
Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method :app_smtp, AppMailDelivery

  # Devise's mailer doesn't inherit ApplicationMailer's default From.
  Devise.mailer_sender = ->(*) { AppSettings.mail_from }
end

# Links in every mailer (Devise's included) point at the app's public URL:
# APP_URL, or the address the admin used during setup.
ActiveSupport.on_load(:action_mailer) do
  prepend(Module.new do
    def default_url_options
      super.merge(AppSettings.url_options)
    end
  end)
end
