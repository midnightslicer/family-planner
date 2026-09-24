require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# The Docker entrypoint generates this secret on first boot. Reading it here
# too means processes that skip the entrypoint (`docker exec`, `kamal app exec
# --reuse`) share the server's secret instead of failing to boot.
secret_file = File.expand_path("../storage/.secret_key_base", __dir__)
if ENV["SECRET_KEY_BASE"].to_s.empty? && ENV["RAILS_MASTER_KEY"].to_s.empty? && File.file?(secret_file)
  ENV["SECRET_KEY_BASE"] = File.read(secret_file).strip
end

module FamilyStatus
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Active Record encryption keys for secrets stored in the database (the
    # SMTP password, TOTP secrets). Keys in credentials win, so installs that
    # already have them keep reading their data. Otherwise they are derived
    # from SECRET_KEY_BASE, which the Docker entrypoint generates and keeps on
    # the storage volume, so a fresh server needs no master key at all.
    key_source = ENV["SECRET_KEY_BASE"].presence || credentials.secret_key_base.presence ||
      ("insecure-#{Rails.env}-only-key" if Rails.env.local?)
    %i[primary_key deterministic_key key_derivation_salt].each do |name|
      value = credentials.dig(:active_record_encryption, name).presence ||
        (OpenSSL::HMAC.hexdigest("SHA256", key_source, "active_record_encryption.#{name}") if key_source)
      config.active_record.encryption.public_send(:"#{name}=", value)
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
