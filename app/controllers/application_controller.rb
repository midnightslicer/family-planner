class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :configure_first_run_gate
  before_action :set_current_household

  helper_method :current_household, :any_users?

  private

  # First-run gate: until the first user exists, every page redirects to the
  # setup wizard. Skipped for the wizard itself and health checks.
  def configure_first_run_gate
    return if controller_name == "setup"
    return if controller_name == "rails/health"

    redirect_to setup_path if User.none?
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    # No database yet — let the setup wizard handle it.
  end

  def any_users?
    @any_users ||= User.any?
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    false
  end

  def set_current_household
    return unless current_user

    household = current_user.households.find_by(id: session[:current_household_id])
    Current.household = household || current_user.households.first
    session[:current_household_id] = Current.household&.id
  end

  def current_household
    Current.household
  end

  def require_household!
    head :not_found unless current_household
  end

  def require_admin!
    head :forbidden unless current_user&.admin?
  end
end