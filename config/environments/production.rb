require "active_support/core_ext/integer/time"
require "uri"

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

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # This prevents CSRF origin mismatches when HTTPS is terminated upstream (for example Caddy/Nginx).
  config.assume_ssl = ActiveModel::Type::Boolean.new.cast(ENV.fetch("ASSUME_SSL", "true"))

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = ActiveModel::Type::Boolean.new.cast(ENV.fetch("FORCE_SSL", "true"))

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

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
  # config.cache_store = :mem_cache_store

  # Default to async jobs so production can run without Redis; set
  # ACTIVE_JOB_QUEUE_ADAPTER=sidekiq when Redis/Sidekiq are available.
  config.active_job.queue_adapter = ENV.fetch("ACTIVE_JOB_QUEUE_ADAPTER", "async").to_sym

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  smtp_address = ENV["SMTP_ADDRESS"].presence
  default_smtp_port = smtp_address.present? ? "587" : "1025"
  default_starttls = smtp_address.present? ? "true" : "false"

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: smtp_address || "127.0.0.1",
    port: ENV.fetch("SMTP_PORT", default_smtp_port).to_i,
    domain: ENV["SMTP_DOMAIN"].presence || ENV.fetch("APP_HOST", "localhost"),
    user_name: ENV["SMTP_USERNAME"].presence,
    password: ENV["SMTP_PASSWORD"].presence,
    authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
    enable_starttls_auto: ActiveModel::Type::Boolean.new.cast(ENV.fetch("SMTP_ENABLE_STARTTLS_AUTO", default_starttls))
  }.compact
  config.action_mailer.default_url_options = {
    host: ENV["APP_HOST"] || "localhost",
    port: (ENV["APP_PORT"] || "443").to_i
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  configured_hosts = [ ENV["APP_HOST"], ENV["ALLOWED_HOSTS"] ]
                     .compact
                     .flat_map { |value| value.to_s.split(",") }
                     .map(&:strip)
                     .filter_map do |value|
                       next if value.blank?

                       begin
                         parsed = URI.parse(value)
                         parsed.host.presence || value
                       rescue URI::InvalidURIError
                         value.sub(%r{\Ahttps?://}i, "").split("/").first
                       end
                     end
                     .uniq
  config.hosts = configured_hosts if configured_hosts.any?
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
