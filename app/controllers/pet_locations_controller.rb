# "Report where": pick pets, pick a location, add a comment if you like.
class PetLocationsController < ApplicationController
  include HouseholdScoped

  # GET /pets/where(?pet_ids[]=..&location_id=..) preselects from a pet's
  # card or after adding a location.
  # The board (PetBoard). `pet_ids` (from a pet's card) are picked already,
  # ready for a tap on their new place.
  def new
    @selected = Array(params[:pet_ids]).map(&:to_i)
    load_choices
  end

  # A move from the board (where_board_controller.js, a turbo stream back:
  # just the flash, since the page morphs itself), or any other form.
  def create
    @check_in = PetCheckIn.new(check_in_params.merge(household: current_household, actor: current_user, kind: "location"))
    saved = @check_in.save
    if request.format.turbo_stream?
      message = saved ? @check_in.summary : @check_in.errors.full_messages.to_sentence
      render turbo_stream: turbo_stream.update("flash", helpers.flash_message(message, saved ? :notice : :alert)),
             status: saved ? :ok : :unprocessable_content
    elsif saved
      redirect_to pets_path, notice: @check_in.summary, status: :see_other
    else
      @selected = @check_in.pet_ids
      load_choices
      render :new, status: :unprocessable_content
    end
  end

  # POST /pets/where/visibility: which pets the board shows (pets that never
  # move can leave it). Anyone in the household can change it, like the
  # rest of a pet's details.
  def visibility
    shown = Array(params[:shown_ids]).compact_blank.map(&:to_i)
    pets = current_household.pets.here
    pets.where(id: shown).where(on_where_page: false).find_each { |pet| pet.update!(on_where_page: true) }
    pets.where.not(id: shown).where(on_where_page: true).find_each { |pet| pet.update!(on_where_page: false) }
    redirect_to new_pet_location_path, notice: "Saved which pets show here.", status: :see_other
  end

  private

  def load_choices
    pets = current_household.pets.here.by_name.with_attached_photo.to_a
    @pets, @hidden = pets.partition(&:on_where_page?)
    @statuses = Pet.statuses(current_household, @pets)
    @board = PetBoard.new(@pets, @statuses, current_household.locations.in_display_order.with_attached_photo)
  end

  def check_in_params
    params.fetch(:check_in, {}).permit(:location_id, :new_location_name, :comment, :spot, :penned, pet_ids: [])
  end
end
