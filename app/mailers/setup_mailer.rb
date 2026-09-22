class SetupMailer < ApplicationMailer
  def test_email
    @app_name = app_name
    mail(to: Setting.get("smtp_from").presence || "test@localhost", subject: "#{app_name}: test email")
  end
end