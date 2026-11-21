# Follow or unfollow a pet (yourself only).
class PetSubscriptionsController < ApplicationController
  include HouseholdScoped

  before_action :set_pet

  def create
    @pet.subscriptions.find_or_create_by!(user: current_user)
    redirect_back_or_to pet_path(@pet), notice: "You'll hear when #{@pet.name} is moved or fed.",
                        status: :see_other, allow_other_host: false
  rescue ActiveRecord::RecordNotUnique
    redirect_back_or_to pet_path(@pet), status: :see_other, allow_other_host: false
  end

  def destroy
    @pet.subscriptions.where(user: current_user).delete_all
    redirect_back_or_to pet_path(@pet), notice: "Stopped following #{@pet.name}.", status: :see_other, allow_other_host: false
  end

  private

  def set_pet
    @pet = current_household.pets.find_by(id: params[:pet_id]) or head :not_found
  end
end
