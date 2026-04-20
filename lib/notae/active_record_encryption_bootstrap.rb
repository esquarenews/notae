module Notae
  module ActiveRecordEncryptionBootstrap
    module_function

    def configure!
      primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].to_s.presence ||
                    credentials_active_record_encryption_value(:primary_key)
      deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].to_s.presence ||
                          credentials_active_record_encryption_value(:deterministic_key)
      key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].to_s.presence ||
                            credentials_active_record_encryption_value(:key_derivation_salt)

      if primary_key.blank? || deterministic_key.blank? || key_derivation_salt.blank?
        secret = encryption_bootstrap_secret
        return if secret.blank?

        primary_key ||= derive_encryption_key(secret, "primary")
        deterministic_key ||= derive_encryption_key(secret, "deterministic")
        key_derivation_salt ||= derive_encryption_key(secret, "salt")
      end

      [ Rails.application.config.active_record.encryption, ActiveRecord::Encryption.config ].each do |encryption_config|
        next if encryption_config.has_primary_key? && encryption_config.has_deterministic_key? && encryption_config.has_key_derivation_salt?

        encryption_config.primary_key = primary_key unless encryption_config.has_primary_key?
        encryption_config.deterministic_key = deterministic_key unless encryption_config.has_deterministic_key?
        encryption_config.key_derivation_salt = key_derivation_salt unless encryption_config.has_key_derivation_salt?
        encryption_config.support_unencrypted_data = true
        encryption_config.extend_queries = true
      end
    end

    def encryption_bootstrap_secret
      configured_secret = ENV["ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET"].to_s.presence ||
                          ENV["SECRET_KEY_BASE"].to_s.presence ||
                          safe_credentials_secret_key_base
      return configured_secret if configured_secret.present?
      return "notae-active-record-encryption-fallback-#{Rails.env}" unless Rails.env.production?

      nil
    end

    def safe_credentials_secret_key_base
      Rails.application.credentials.secret_key_base.to_s.presence
    rescue ActiveSupport::MessageEncryptor::InvalidMessage,
           ActiveSupport::EncryptedFile::MissingKeyError,
           ArgumentError
      nil
    end

    def credentials_active_record_encryption_value(key_name)
      config_hash = Rails.application.credentials[:active_record_encryption]
      return nil unless config_hash.respond_to?(:[])

      value = config_hash[key_name] || config_hash[key_name.to_s]
      value.to_s.strip.presence
    rescue ActiveSupport::MessageEncryptor::InvalidMessage,
           ActiveSupport::EncryptedFile::MissingKeyError,
           ArgumentError
      nil
    end

    def derive_encryption_key(secret, context)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "notae:active-record-encryption:#{context}")
    end
  end
end
