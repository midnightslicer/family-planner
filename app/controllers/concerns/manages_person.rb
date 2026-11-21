# Pages about a person's own details (work schedule, days off, profile)
# act on yourself, or, for an admin, on any member of the current
# household named by `person_id`, so they can keep things up to date for
# someone less at home with the app. Anyone else naming another person gets
# a 404. Sign-in security (password, passkeys, 2-step) is never managed
# this way.
module ManagesPerson
  extend ActiveSupport::Concern

  included do
    helper_method :managed_person, :managing_someone_else?, :managed_person_param
  end

  private

  def managed_person
    return @managed_person if defined?(@managed_person)

    id = params[:person_id].to_s
    @managed_person =
      if id.blank? || id == current_user.id.to_s then current_user
      elsif current_user.admin? then current_household.users.find_by(id: id)
      end
  end

  def require_managed_person
    head :not_found unless managed_person
  end

  def managing_someone_else?
    managed_person != current_user
  end

  # For links and redirects back to the same person's page.
  def managed_person_param
    managing_someone_else? ? { person_id: managed_person.id } : {}
  end

  def announce_change_for(person)
    person.broadcast_card
    person.households.each(&:broadcast_refresh)
  end
end
