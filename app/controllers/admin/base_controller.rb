module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin

    private

    def require_admin
      head :forbidden unless current_user&.admin?
    end
  end
end