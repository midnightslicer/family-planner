module Admin
  # Removes someone from a household (their account stays).
  class MembershipsController < BaseController
    def destroy
      membership = HouseholdMembership.find_by!(household_id: params[:household_id], id: params[:id])
      membership.destroy
      redirect_to edit_admin_household_path(params[:household_id]),
                  notice: "#{membership.user.display_name} was removed from the household.", status: :see_other
    end
  end
end
