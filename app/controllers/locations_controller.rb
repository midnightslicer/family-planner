class LocationsController < ApplicationController
  include HouseholdScoped

  before_action :set_location, only: [:edit, :update, :destroy]
  before_action -> { require_creator_or_admin(@location) }, only: :destroy

  # GET /locations: every place, and who's there right now.
  def index
    @locations = current_household.locations.in_display_order.with_attached_photo
    @pets = current_household.pets.by_name.with_attached_photo
    pet_reports = LocationReport.latest_for(current_household, "Pet", @pets.map(&:id))
    @members = current_household.members_by_name.with_attached_avatar
    people_reports = LocationReport.latest_for(current_household, "User", @members.map(&:id))
    @here = Hash.new { |hash, key| hash[key] = [] }
    @pets.each { |pet| @here[pet_reports[pet.id]&.location_id] << pet if pet_reports[pet.id] }
    @members.each { |user| @here[people_reports[user.id]&.location_id] << user if people_reports[user.id] }
  end

  def new
    @location = current_household.locations.new(kind: params[:kind].presence_in(Location::KINDS) || "other")
  end

  def create
    @location = current_household.locations.new(location_params.merge(created_by: current_user))
    if @location.save
      redirect_to locations_path, notice: "Added #{@location.name}.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @location.update(location_params)
      redirect_to locations_path, notice: "Saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @location.destroy
    redirect_to locations_path, notice: "Removed #{@location.name}.", status: :see_other
  end

  private

  def set_location
    @location = current_household.locations.find_by(id: params[:id]) or head :not_found
  end

  def location_params
    params.require(:location).permit(:name, :kind, :photo, :remove_photo)
  end
end
