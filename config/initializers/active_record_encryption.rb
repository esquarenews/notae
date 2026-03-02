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

  encrypted_credentials = Rails.application.credentials
  credentials_encryption = begin
    raw = encrypted_credentials[:active_record_encryption] || encrypted_credentials["active_record_encryption"]
    raw.respond_to?(:to_h) ? raw.to_h : {}
  rescue StandardError
    {}
  end
  credentials_encryption_value = lambda do |name|
    value = credentials_encryption[name.to_sym]
    value = credentials_encryption[name.to_s] if value.blank?
    value.to_s.strip.presence
  end

  credentials_secret = begin
    encrypted_credentials.secret_key_base.to_s
  rescue ActiveSupport::MessageEncryptor::InvalidMessage,
         ActiveSupport::EncryptedFile::MissingKeyError,
         ArgumentError => error
    if Rails.env.production? && ENV["SECRET_KEY_BASE"].blank?
      raise error
    end

    Rails.logger.warn("[EncryptionConfig] Falling back without credentials.secret_key_base: #{error.class}: #{error.message}")
    ""
  end

  secret = ENV["ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET"].to_s
  secret = ENV["SECRET_KEY_BASE"].to_s if secret.blank?
  secret = credentials_secret if secret.blank?
  secret = ENV["SECRET_KEY_BASE_DUMMY"].to_s if secret.blank?
  secret = "notae-active-record-encryption-fallback-#{Rails.env}" if secret.blank?

  derive = lambda do |context|
    OpenSSL::HMAC.hexdigest("SHA256", secret, "notae:active-record-encryption:#{context}")
  end

  config.active_record.encryption.primary_key = (
    ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
    credentials_encryption_value.call(:primary_key) ||
    config.active_record.encryption.primary_key.presence ||
    derive.call("primary")
  )
  config.active_record.encryption.deterministic_key = (
    ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
    credentials_encryption_value.call(:deterministic_key) ||
    config.active_record.encryption.deterministic_key.presence ||
    derive.call("deterministic")
  )
  config.active_record.encryption.key_derivation_salt = (
    ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
    credentials_encryption_value.call(:key_derivation_salt) ||
    config.active_record.encryption.key_derivation_salt.presence ||
    derive.call("salt")
  )

  if Rails.env.production? && !running_assets_task
    unless config.active_record.encryption.primary_key.present? &&
           config.active_record.encryption.deterministic_key.present? &&
           config.active_record.encryption.key_derivation_salt.present?
      raise <<~ERROR.squish
        Missing Active Record encryption keys in production.
        Set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY,
        and ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT (or config/credentials production equivalents).
      ERROR
    end
  end

  config.active_record.encryption.support_unencrypted_data = true
  config.active_record.encryption.extend_queries = true
end
