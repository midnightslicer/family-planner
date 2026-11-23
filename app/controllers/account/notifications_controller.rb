module Account
  # The Notifications page: this device, which kinds of update reach you by
  # push and/or email, quiet hours and pause, and your devices. Always your
  # own: admins don't manage other people's (like sign-in security), and no
  # user id is ever read from params.
  class NotificationsController < BaseController
    PAUSE_HOURS = [1, 8, 24].freeze

    before_action :load_page, only: :show

    def show
    end

    # Saves whatever part of the page was sent: the push/email matrix (and
    # its two selects), or quiet hours. A column that's unavailable (no
    # SMTP, no VAPID key) is disabled on the page, so its boxes don't
    # submit; their stored values are left exactly as they were.
    def update
      settings = params.fetch(:notifications, {})
      @user = current_user
      @user.assign_attributes(scalar_settings(settings))
      if @user.valid?
        User.transaction do
          save_matrix(settings[:categories]) if settings[:categories].respond_to?(:each_pair)
          @user.save!
        end
        redirect_to account_notifications_path, notice: "Notification settings saved."
      else
        load_page
        render :show, status: :unprocessable_content
      end
    end

    def pause
      hours = params[:hours].to_i
      return head(:unprocessable_content) unless PAUSE_HOURS.include?(hours)

      current_user.update!(notifications_paused_until: hours.hours.from_now)
      redirect_to account_notifications_path(anchor: "quiet"),
                  notice: "Pushes paused until #{helpers.paused_until_text(current_user.notifications_paused_until)}."
    end

    def resume
      current_user.update!(notifications_paused_until: nil)
      redirect_to account_notifications_path(anchor: "quiet"), notice: "Pushes are back on."
    end

    private

    def load_page
      @user ||= current_user
      @devices = current_user.push_subscriptions.order(:created_at).to_a
      @matrix = NotificationPreference.matrix_for(current_user)
      @email_available = AppSettings.smtp_configured?
      @push_available = PushKeys.available?
    end

    def scalar_settings(settings)
      attributes = settings.slice(:reminder_lead_minutes, :digest_hour).to_unsafe_h
      if settings.key?(:quiet_hours)
        on = settings[:quiet_hours] == "1"
        attributes[:quiet_hours_start] = (settings[:quiet_hours_start] if on)
        attributes[:quiet_hours_end] = (settings[:quiet_hours_end] if on)
      end
      attributes
    end

    def save_matrix(categories)
      push_available = PushKeys.available?
      email_available = AppSettings.smtp_configured?
      NotificationPreference::CATEGORIES.each_key do |key|
        values = categories[key]
        next unless values.respond_to?(:key?)

        preference = current_user.notification_preferences.find_or_initialize_by(category: key)
        preference.push = checked?(values[:push]) if push_available && values.key?(:push)
        preference.email = checked?(values[:email]) if email_available && values.key?(:email)
        preference.save!
      end
    end

    def checked?(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end
  end
end
