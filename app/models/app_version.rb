# The app's version, shown at the foot of the account page, and what changed
# in each one (config/changelog.yml, newest first). After an update everyone
# sees "What's new" once (layouts/_changelog): users.last_seen_version says
# which version they last closed it on. New accounts start on the current
# one, so they aren't told about changes they never saw.
#
# A release: bump CURRENT and add its entry at the top of the changelog.
module AppVersion
  CURRENT = "1.1".freeze

  def self.changelog
    @changelog ||= YAML.load_file(Rails.root.join("config/changelog.yml"), permitted_classes: [ Date ])
                       .map { |release| release.symbolize_keys.freeze }.freeze
  end

  def self.unseen_by?(user)
    user.last_seen_version.blank? || Gem::Version.new(user.last_seen_version) < Gem::Version.new(CURRENT)
  end
end
