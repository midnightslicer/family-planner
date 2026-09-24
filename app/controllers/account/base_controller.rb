module Account
  class BaseController < ApplicationController
    before_action :authenticate_user!

    private

    def load_account_page
      @user = current_user
      @passkeys = current_user.passkeys.order(:created_at)
    end
  end
end
