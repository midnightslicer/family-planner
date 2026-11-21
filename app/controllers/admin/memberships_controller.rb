module Admin
  # Household members: which house each lives in, or removing someone from
  # the household (their account stays).
  class MembershipsController < BaseController
    def update
      membership = HouseholdMembership.find_by!(household_id: params[:household_id], id: params[:id])
      home = membership.household.locations.find_by(id: params.dig(:household_membership, :home_id))
      membership.update!(home: home)
      membership.household.broadcast_refresh
      redirect_to edit_admin_household_path(params[:household_id]),
                  notice: "#{membership.user.display_name} lives at #{home&.name || 'no house set'}.", status: :see_other
    end

    def destroy
      membership = HouseholdMembership.find_by!(household_id: params[:household_id], id: params[:id])
      membership.destroy
      redirect_to edit_admin_household_path(params[:household_id]),
                  notice: "#{membership.user.display_name} was removed from the household.", status: :see_other
    end
  end
end
