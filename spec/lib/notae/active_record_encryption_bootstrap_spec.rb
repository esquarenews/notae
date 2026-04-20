require "rails_helper"

RSpec.describe Notae::ActiveRecordEncryptionBootstrap do
  it "derives encryption keys from SECRET_KEY_BASE outside controller requests" do
    runtime_config = ActiveRecord::Encryption.config
    app_config = Rails.application.config.active_record.encryption
    original_values = {
      runtime_primary: runtime_config.instance_variable_get(:@primary_key),
      runtime_deterministic: runtime_config.instance_variable_get(:@deterministic_key),
      runtime_salt: runtime_config.instance_variable_get(:@key_derivation_salt),
      app_primary: app_config.instance_variable_get(:@primary_key),
      app_deterministic: app_config.instance_variable_get(:@deterministic_key),
      app_salt: app_config.instance_variable_get(:@key_derivation_salt),
      env_primary: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
      env_deterministic: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
      env_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"],
      env_bootstrap: ENV["ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET"],
      env_secret_key_base: ENV["SECRET_KEY_BASE"]
    }

    runtime_config.instance_variable_set(:@primary_key, nil)
    runtime_config.instance_variable_set(:@deterministic_key, nil)
    runtime_config.instance_variable_set(:@key_derivation_salt, nil)
    app_config.instance_variable_set(:@primary_key, nil)
    app_config.instance_variable_set(:@deterministic_key, nil)
    app_config.instance_variable_set(:@key_derivation_salt, nil)
    ENV.delete("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY")
    ENV.delete("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY")
    ENV.delete("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")
    ENV.delete("ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET")
    ENV["SECRET_KEY_BASE"] = "bootstrap-secret-for-spec"

    described_class.configure!

    expect(runtime_config.instance_variable_get(:@primary_key)).to eq(
      described_class.derive_encryption_key("bootstrap-secret-for-spec", "primary")
    )
    expect(runtime_config.instance_variable_get(:@deterministic_key)).to eq(
      described_class.derive_encryption_key("bootstrap-secret-for-spec", "deterministic")
    )
    expect(runtime_config.instance_variable_get(:@key_derivation_salt)).to eq(
      described_class.derive_encryption_key("bootstrap-secret-for-spec", "salt")
    )
    expect(runtime_config.has_primary_key?).to be_present
    expect(runtime_config.has_deterministic_key?).to be_present
    expect(runtime_config.has_key_derivation_salt?).to be_present
  ensure
    runtime_config.instance_variable_set(:@primary_key, original_values[:runtime_primary]) if runtime_config
    runtime_config.instance_variable_set(:@deterministic_key, original_values[:runtime_deterministic]) if runtime_config
    runtime_config.instance_variable_set(:@key_derivation_salt, original_values[:runtime_salt]) if runtime_config
    app_config.instance_variable_set(:@primary_key, original_values[:app_primary]) if app_config
    app_config.instance_variable_set(:@deterministic_key, original_values[:app_deterministic]) if app_config
    app_config.instance_variable_set(:@key_derivation_salt, original_values[:app_salt]) if app_config
    ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] = original_values[:env_primary]
    ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] = original_values[:env_deterministic]
    ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] = original_values[:env_salt]
    ENV["ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET"] = original_values[:env_bootstrap]
    ENV["SECRET_KEY_BASE"] = original_values[:env_secret_key_base]
  end
end
