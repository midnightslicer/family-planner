class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  before_action :set_app_name

  private

  def app_name
    Setting.get("app_name").presence || "Family Status"
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    "Family Status"
  end

  def set_app_name
    @app_name = app_name
  end
end