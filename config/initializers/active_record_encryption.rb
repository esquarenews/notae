require "openssl"

Rails.application.configure do
  running_assets_task = begin
    if defined?(::Rake) && ::Rake.respond_to?(:application) && ::Rake.application
      Array(::Rake.application.top_level_tasks).any? { |task| task.to_s.start_with?("assets:") }
    else
      Array(ARGV).any? { |arg| arg.to_s.start_with?("assets:") }
    end
  rescue StandardError
    Array(ARGV).any? { |arg| arg.to_s.start_with?("assets:") }
  end

  credentials_secret = begin
    Rails.application.credentials.secret_key_base.to_s
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::EncryptedFile::MissingKeyError => error
    if Rails.env.production? && ENV["SECRET_KEY_BASE"].blank?
      raise error
    end

    Rails.logger.warn("[EncryptionConfig] Falling back without credentials.secret_key_base: #{error.class}: #{error.message}")
    ""
  end

  secret = ENV["SECRET_KEY_BASE"].to_s
  secret = credentials_secret if secret.blank?
  secret = ENV["SECRET_KEY_BASE_DUMMY"].to_s if secret.blank?

  if secret.blank?
    if Rails.env.production? && !running_assets_task
      raise "Missing SECRET_KEY_BASE for Active Record encryption setup in production (or provide credentials.secret_key_base)"
    end

    secret = "notae-active-record-encryption-fallback-#{Rails.env}"
  end
  derive = lambda do |context|
    OpenSSL::HMAC.hexdigest("SHA256", secret, "notae:active-record-encryption:#{context}")
  end

  config.active_record.encryption.primary_key =
    ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
    config.active_record.encryption.primary_key.presence ||
    derive.call("primary")
  config.active_record.encryption.deterministic_key =
    ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
    config.active_record.encryption.deterministic_key.presence ||
    derive.call("deterministic")
  config.active_record.encryption.key_derivation_salt =
    ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
    config.active_record.encryption.key_derivation_salt.presence ||
    derive.call("salt")
  config.active_record.encryption.support_unencrypted_data = true
  config.active_record.encryption.extend_queries = true
end
