class SetupMailer < ApplicationMailer
  def test_email(recipient)
    mail(to: recipient, subject: "#{@app_name}: test email")
  end
end
