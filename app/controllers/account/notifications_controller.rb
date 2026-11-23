module Account
  # The Notifications page: this device, and every device that gets your
  # pushes. Always your own; admins don't manage other people's (like
  # sign-in security).
  class NotificationsController < BaseController
    def show
      @devices = current_user.push_subscriptions.order(:created_at).to_a
    end
  end
end
