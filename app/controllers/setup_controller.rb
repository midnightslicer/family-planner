# First-run setup wizard. Step 1: app settings (name + SMTP, with a send
# test email action). Step 2: the first admin account. Completing step 2
# creates the admin, a default household named after the app, signs in, and
# redirects to the dashboard.
class SetupController < ApplicationController
  before_action :require_no_users!
  before_action :skip_if_setup_complete

  SETTINGS_KEYS = %w[app_name smtp_host smtp_port smtp_user smtp_password smtp_from smtp_tls].freeze

  def show
    @settings = settings_hash
  end

  def update_settings
    SETTINGS_KEYS.each do |key|
      Setting.set(key, params.dig(:settings, key).presence)
    end
    redirect_to setup_account_path
  end

  def test_email
    if smtp_configured?
      SetupMailer.test_email.deliver_later
      redirect_back(fallback_location: setup_path, notice: "Test email sent — check the letter_opener preview (dev) or your inbox.")
    else
      redirect_back(fallback_location: setup_path, alert: "SMTP is not configured — fill in the SMTP fields first.")
    end
  end

  def account
    @user = User.new
    @app_name = Setting.get("app_name").presence || "Family Status"
  end

  def create_account
    @user = User.new(user_params.merge(admin: true))
    @app_name = Setting.get("app_name").presence || "Family Status"

    if @user.save
      household = Household.create!(name: @app_name)
      @user.household_memberships.create!(household: household)
      sign_in @user
      redirect_to dashboard_path, notice: "Welcome! Your household is ready."
    else
      render :account, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:display_name, :handle, :email, :password, :password_confirmation, :color)
  end

  def settings_hash
    SETTINGS_KEYS.index_with { |key| Setting.get(key) }
  end

  def smtp_configured?
    Setting.get("smtp_host").present?
  end

  def require_no_users!
    redirect_to dashboard_path if User.any?
  end

  def skip_if_setup_complete
    true
  end
end