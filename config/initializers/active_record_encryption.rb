require "openssl"

Rails.application.configure do
  secret = Rails.application.secret_key_base.to_s
  secret = ENV["SECRET_KEY_BASE"].to_s if secret.blank?
  if secret.blank?
    if Rails.env.production?
      raise "Missing SECRET_KEY_BASE for Active Record encryption setup in production"
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
