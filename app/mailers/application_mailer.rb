class ApplicationMailer < ActionMailer::Base
  default from: -> { AppSettings.mail_from }
  layout "mailer"

  before_action :set_app_name

  private

  def set_app_name
    @app_name = AppSettings.app_name
  end
end
