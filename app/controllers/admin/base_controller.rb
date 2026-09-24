module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    before_action :remember_app_url

    private

    # Installs set up before app_url existed learn it from the first admin
    # visit (an admin's own request, so its Host header can be trusted).
    def remember_app_url
      Setting.set("app_url", request.base_url) if AppSettings.app_url.blank?
    end
  end
end
