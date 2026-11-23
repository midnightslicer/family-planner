# One email per update, for people who chose email for that kind of update
# on the Notifications page (Notifier decides). Every one says why it came
# and carries a one-click unsubscribe for its category, in the footer and
# in the List-Unsubscribe headers (RFC 8058) that mail apps turn into
# their own button. Links use AppSettings.url_options, never a request.
class NotificationMailer < ApplicationMailer
  def update(user, category:, title:, body:, path:, household:)
    @user = user
    @category = NotificationPreference.category(category)
    @title = title
    @detail = body
    @household = household
    @open_url = absolute(path)
    @settings_url = account_notifications_url
    @unsubscribe_url = notification_unsubscribe_url(NotificationUnsubscribe.token_for(user, @category.key))

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    prefix = household ? "[#{household.name}] " : ""
    mail(to: user.email, subject: "#{prefix}#{title}".truncate(150))
  end

  private

  # A path from Notifier.link (always "/..."), on the app's public address.
  def absolute(path)
    path = "/" unless path.to_s.start_with?("/") && !path.to_s.start_with?("//")
    root_url.delete_suffix("/") + path
  end

  def root_url
    dashboard_root_url
  end
end
