module Admin
  class HouseholdsController < BaseController
    before_action :set_household, only: [:edit, :update, :destroy]

    def index
      @households = Household.left_joins(:household_memberships)
                             .select("households.*, COUNT(household_memberships.id) AS members_count")
                             .group("households.id").order(:name)
      @household = Household.new
    end

    def create
      @household = Household.new(household_params)
      if @household.save
        @household.household_memberships.create!(user: current_user)
        redirect_to admin_root_path, notice: "Household created. You're a member, so it's in your household switcher."
      else
        @households = Household.order(:name)
        render :index, status: :unprocessable_content
      end
    end

    def edit
      @members = @household.household_memberships.eager_load(:user).order("users.display_name")
    end

    def update
      if @household.update(household_params)
        redirect_to admin_root_path, notice: "Household updated."
      else
        @members = @household.household_memberships.eager_load(:user).order("users.display_name")
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @household.destroy
      redirect_to admin_root_path, notice: "Household deleted.", status: :see_other
    end

    private

    def set_household
      @household = Household.find(params[:id])
    end

    def household_params
      params.require(:household).permit(:name, :slug, :time_zone)
    end
  end
end
