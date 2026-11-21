module Account
  # The account page: profile, sign-in methods (password, passkeys) and
  # two-factor authentication, for every member.
  class ProfilesController < BaseController
    before_action :load_account_page

    def show
    end

    def update
      if ProfileUpdate.new(@user, household: current_household, params: params).save
        redirect_to account_root_path, notice: "Profile saved."
      else
        render :show, status: :unprocessable_content
      end
    end
  end
end
