module Account
  class BaseController < ApplicationController
    before_action :authenticate_user!

    private

    def load_account_page
      @user = current_user
      @passkeys = current_user.passkeys.order(:created_at)
      @checklist = GettingStarted.new(current_user, current_household) if current_household
    end
  end
end
