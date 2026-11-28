module Account
  # "What's new" was closed (layouts/_changelog): it stays away until the
  # next version (AppVersion).
  class ChangelogsController < BaseController
    def seen
      current_user.update_column(:last_seen_version, AppVersion::CURRENT)
      head :no_content
    end
  end
end
