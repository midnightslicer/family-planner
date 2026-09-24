require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Kamal's proxy (or Caddy, Traefik...) terminates TLS in front of the app.
  # Set FORCE_SSL=false only for plain-http LAN installs; passkeys and
  # notifications need https (or localhost) and will be hidden without it.
  force_ssl = ENV.fetch("FORCE_SSL", "true") != "false"
  config.assume_ssl = force_ssl
  config.force_ssl = force_ssl
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # SMTP details live in the database (Admin -> Settings) with SMTP_* env vars
  # as a fallback, and AppMailDelivery reads them at send time, so changes
  # apply without a restart. Links in emails use APP_URL or the URL recorded
  # during setup (see config/initializers/mailer.rb).
  config.action_mailer.delivery_method = :app_smtp
  config.action_mailer.raise_delivery_errors = true

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # DNS rebinding / Host header protection. APP_URL's host is always allowed;
  # add others (a LAN name, say) as a comma-separated APP_HOSTS.
  allowed_hosts = ENV.fetch("APP_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
  allowed_hosts << URI(ENV["APP_URL"]).host if ENV["APP_URL"].present?
  if allowed_hosts.any?
    config.hosts = allowed_hosts
    config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  end
end
