# "Feed": pick pets (their feeding notes are right there), add a comment if
# you like. A pet card's one-tap "Fed" button posts here too.
class FeedingsController < ApplicationController
  include HouseholdScoped

  def new
    @check_in = PetCheckIn.new(household: current_household, kind: "feeding", pet_ids: params[:pet_ids])
    load_choices
  end

  def create
    @check_in = PetCheckIn.new(check_in_params.merge(household: current_household, actor: current_user, kind: "feeding"))
    if @check_in.save
      # A card's one-tap button stays on the page it was on; the full form
      # goes to the cards, where the result shows.
      if params[:quick]
        redirect_back_or_to pets_path, notice: @check_in.summary, status: :see_other, allow_other_host: false
      else
        redirect_to pets_path, notice: @check_in.summary, status: :see_other
      end
    else
      load_choices
      render :new, status: :unprocessable_content
    end
  end

  # DELETE /feedings/:id: take back a meal recorded by mistake.
  def destroy
    feeding = current_household.feedings.find_by(id: params[:id]) or return head(:not_found)
    return head(:forbidden) unless feeding.fed_by_id == current_user.id || current_user.admin?

    feeding.destroy
    redirect_back_or_to pet_path(feeding.pet), notice: "Removed that meal.", status: :see_other, allow_other_host: false
  end

  private

  def load_choices
    @pets = current_household.pets.by_name.with_attached_photo
    @statuses = Pet.statuses(current_household, @pets)
  end

  def check_in_params
    params.fetch(:check_in, {}).permit(:comment, pet_ids: [])
  end
end
