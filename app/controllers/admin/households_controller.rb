module Admin
  class HouseholdsController < BaseController
    def index
      @households = Household.order(:name)
      @household = Household.new
    end

    def create
      @household = Household.new(household_params)
      if @household.save
        redirect_to admin_root_path, notice: "Household created."
      else
        @households = Household.order(:name)
        render :index, status: :unprocessable_entity
      end
    end

    def edit
      @household = Household.find(params[:id])
    end

    def update
      @household = Household.find(params[:id])
      if @household.update(household_params)
        redirect_to admin_root_path, notice: "Household updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @household = Household.find(params[:id])
      @household.destroy
      redirect_to admin_root_path, notice: "Household deleted.", status: :see_other
    end

    private

    def household_params
      params.require(:household).permit(:name)
    end
  end
end