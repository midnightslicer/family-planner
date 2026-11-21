# An admin's "Manage profile" for another member: the same profile form as
# the account page (ProfileUpdate), plus links to their work schedule and
# days off. Your own goes to your account page. Never sign-in security:
# that stays with the person (Admin > People has reset tools).
class PersonProfilesController < ApplicationController
  include HouseholdScoped
  include ManagesPerson

  before_action :require_managed_person
  before_action :own_profile_lives_on_the_account_page

  def edit
    @user = managed_person
  end

  def update
    @user = managed_person
    if ProfileUpdate.new(@user, household: current_household, params: params).save
      redirect_to edit_person_profile_path(@user), notice: "Saved #{@user.display_name}'s profile.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def own_profile_lives_on_the_account_page
    redirect_to account_root_path unless managing_someone_else?
  end
end
