# "Report where": pick pets, pick a location, add a comment if you like.
class PetLocationsController < ApplicationController
  include HouseholdScoped

  # GET /pets/where(?pet_ids[]=..&location_id=..) preselects from a pet's
  # card or after adding a location.
  def new
    @check_in = PetCheckIn.new(household: current_household, kind: "location",
                               pet_ids: params[:pet_ids], location_id: params[:location_id])
    load_choices
  end

  def create
    @check_in = PetCheckIn.new(check_in_params.merge(household: current_household, actor: current_user, kind: "location"))
    if @check_in.save
      redirect_to pets_path, notice: @check_in.summary, status: :see_other
    else
      load_choices
      render :new, status: :unprocessable_content
    end
  end

  private

  def load_choices
    @pets = current_household.pets.here.by_name.with_attached_photo
    @statuses = Pet.statuses(current_household, @pets)
    @locations = current_household.locations.in_display_order.with_attached_photo
  end

  def check_in_params
    params.fetch(:check_in, {}).permit(:location_id, :new_location_name, :comment, :spot, pet_ids: [])
  end
end
