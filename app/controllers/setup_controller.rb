# First-run setup: one page that names the household and creates the first
# (admin) account. Email/SMTP is optional and lives in Admin > Settings.
#
# A fresh server is open to whoever reaches it first, so outside development
# the page asks for the setup code printed in the server's log at boot (see
# AppSettings.setup_code). Opening /setup?code=... skips typing it.
class SetupController < ApplicationController
  include AccountSignup

  skip_before_action :require_setup
  before_action :require_no_users!
  before_action :require_unlocked, except: :unlock
  rate_limit to: 10, within: 5.minutes, only: :unlock, with: -> {
    redirect_to setup_path, alert: "Too many attempts. Wait a few minutes and try again."
  }

  def show
    @user = User.new(color: User.suggested_color)
    @household_name = ""
  end

  def unlock
    if AppSettings.valid_setup_code?(params[:code])
      session[:setup_unlocked] = true
      redirect_to setup_path
    else
      flash.now[:alert] = "That setup code doesn't match. Copy it from the server log (or run bin/rails setup:code)."
      render :unlock, status: :unprocessable_content
    end
  end

  def passkey_options
    render_signup_passkey_options(User.new(signup_params))
  end

  def create
    @household_name = params[:household_name].to_s.strip.presence || "Home"
    @user = User.new(signup_params.merge(admin: true))

    if attach_signup_passkey(@user) && create_first_account
      session.delete(:setup_unlocked)
      sign_in(:user, @user)
      redirect_to dashboard_path, notice: "You're all set. Next, invite your family."
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def create_first_account
    created = false
    User.transaction do
      raise ActiveRecord::Rollback if User.exists? || !@user.save

      household = Household.create!(name: @household_name)
      @user.household_memberships.create!(household: household)
      Setting.set("app_name", @household_name) if Setting.get("app_name").blank?
      # Links in emails need the public address; this is the one the admin
      # is using right now. Editable in Admin > Settings; APP_URL overrides.
      Setting.set("app_url", request.base_url) if Setting.get("app_url").blank?
      created = true
    end
    created
  end

  def require_no_users!
    redirect_to dashboard_path if User.exists?
  end

  def require_unlocked
    return if !AppSettings.setup_code_required? || session[:setup_unlocked]

    if params[:code].present? && AppSettings.valid_setup_code?(params[:code])
      session[:setup_unlocked] = true
      redirect_to setup_path if request.get?
    else
      render :unlock, status: (request.get? ? :ok : :forbidden), formats: :html
    end
  end
end
