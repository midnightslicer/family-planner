# Action Mailer delivery method that looks up SMTP settings at send time
# (registered as :app_smtp in config/initializers/mailer.rb).
class AppMailDelivery
  class NotConfigured < StandardError; end

  attr_accessor :settings

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    smtp = AppSettings.smtp_settings
    raise NotConfigured, "Email isn't set up yet. Add SMTP details under Admin > Settings." unless smtp

    Mail::SMTP.new(smtp).deliver!(mail)
  end
end
