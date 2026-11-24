class PetsController < ApplicationController
  include HouseholdScoped

  HISTORY_LIMIT = 15

  before_action :set_pet, only: [:show, :edit, :update, :destroy, :away, :back]
  before_action -> { require_creator_or_admin(@pet) }, only: :destroy

  # GET /pets: every pet's card, with what to do next right on it.
  def index
    @pets = current_household.pets.here.by_name.with_attached_photo
    @statuses = Pet.statuses(current_household, @pets)
    @away = current_household.pets.away.by_name.with_attached_photo
  end

  # GET /pets/:id: the pet's profile and its recent comings and goings.
  def show
    @status = @pet.status
    @history = (@pet.location_reports.recent.limit(HISTORY_LIMIT) + @pet.feedings.recent.limit(HISTORY_LIMIT))
               .sort_by(&:created_at).reverse.first(HISTORY_LIMIT)
  end

  def new
    @pet = current_household.pets.new(home: current_household.locations.where(kind: "house").order(:id).first)
  end

  def create
    @pet = current_household.pets.new(pet_params.merge(created_by: current_user))
    choose_species
    choose_home
    if @pet.save
      redirect_to pet_path(@pet), notice: "Added #{@pet.name}.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @pet.assign_attributes(pet_params)
    choose_species
    choose_home
    if @pet.save
      # A photo saves as soon as it's cropped: stay on the form you're editing.
      if params[:photo_autosave].present?
        redirect_to edit_pet_path(@pet), notice: "Photo saved.", status: :see_other
      else
        redirect_to pet_path(@pet), notice: "Saved.", status: :see_other
      end
    else
      render :edit, status: :unprocessable_content
    end
  end

  # POST /pets/:id/away: not here for now (a dog we sit went home). Kept,
  # with its history, under Away on the pets page.
  # Only for pets we sit: our own pets don't come and go.
  def away
    unless @pet.visitor?
      return redirect_to pet_path(@pet), alert: "Only pets you sit can be marked away.", status: :see_other
    end

    @pet.leave!
    redirect_to pets_path, notice: "#{@pet.name} is marked away. Find them under Away when they're back.", status: :see_other
  end

  # POST /pets/:id/back
  def back
    @pet.arrive!
    redirect_to pet_path(@pet), notice: "#{@pet.name} is back. Where are they?", status: :see_other
  end

  def destroy
    @pet.archive!
    redirect_to pets_path, notice: "Removed #{@pet.name}. Their history is kept.", status: :see_other
  end

  private

  def set_pet
    @pet = current_household.pets.find_by(id: params[:id]) or not_found
  end

  def pet_params
    params.require(:pet).permit(:name, :species, :birthday, :meals_per_day, :feeding_notes, :photo, :remove_photo, :visitor, :on_wall)
  end

  # The type menu's "New type…" takes the name typed beside it.
  def choose_species
    @new_species = params.dig(:pet, :new_species)
    @pet.species = @new_species if @pet.species == Pet::NEW_KIND
  end

  # "Sleeps at" is an existing location, nothing, or a new house typed in
  # the form (saved along with the pet).
  def choose_home
    home_id = params.dig(:pet, :home_id)
    @new_home_name = params.dig(:pet, :new_home_name)
    @pet.home = home_id.blank? ? nil : Location.chosen(current_household, home_id, new_name: @new_home_name, kind: "house", created_by: current_user)
  end
end
