require "openssl"

Rails.application.configure do
  next if config.active_record.encryption.primary_key.present?

  secret = Rails.application.secret_key_base.to_s
  derive = lambda do |context|
    OpenSSL::HMAC.hexdigest("SHA256", secret, "notae:active-record-encryption:#{context}")
  end

  config.active_record.encryption.primary_key = [
    ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || derive.call("primary")
  ]
  config.active_record.encryption.deterministic_key = [
    ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || derive.call("deterministic")
  ]
  config.active_record.encryption.key_derivation_salt =
    ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || derive.call("salt")
  config.active_record.encryption.support_unencrypted_data = true
  config.active_record.encryption.extend_queries = true
end
