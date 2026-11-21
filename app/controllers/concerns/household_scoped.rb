# For pages that only make sense inside the current household: signed in, a
# household chosen, and records looked up through it (another household's
# id is a 404, never a 403).
module HouseholdScoped
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    before_action :require_household!
  end

  private

  # Whoever added it, or an admin. Everyone else in the household can still
  # use and edit it.
  def require_creator_or_admin(record)
    head :forbidden unless record.created_by_id == current_user.id || current_user.admin?
  end
end
