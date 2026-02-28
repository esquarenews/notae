require "rails_helper"

RSpec.describe User, type: :model do
  it "requires email for authentication" do
    user = described_class.new(password: "password123")

    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("can't be blank")
  end

  it "has workspace memberships" do
    association = described_class.reflect_on_association(:memberships)

    expect(association.macro).to eq(:has_many)
  end

  it "requires complete SMTP settings when any SMTP field is provided" do
    user = described_class.new(email: "smtp-user@example.com", password: "password123", smtp_address: "smtp.example.com")

    expect(user).not_to be_valid
    expect(user.errors[:smtp_port]).to include("can't be blank")
    expect(user.errors[:smtp_username]).to include("can't be blank")
    expect(user.errors[:smtp_password]).to include("can't be blank")
    expect(user.errors[:smtp_from_email]).to include("can't be blank")
  end

  it "reports SMTP configuration and sender display values" do
    user = described_class.new(
      email: "smtp-ready@example.com",
      password: "password123",
      smtp_address: "smtp.example.com",
      smtp_port: 587,
      smtp_username: "smtp-user",
      smtp_password: "smtp-password-123",
      smtp_from_name: "Notae Bot",
      smtp_from_email: "noreply@example.com"
    )

    expect(user.smtp_configured?).to be(true)
    expect(user.smtp_from_display).to eq("Notae Bot <noreply@example.com>")
    expect(user.masked_smtp_password).to eq("sm...23")
  end

  it "encrypts AI and SMTP credential fields at rest" do
    user = described_class.create!(
      email: "encrypted-credentials@example.com",
      password: "password123",
      openai_api_key: "sk-test-abc123",
      smtp_address: "smtp.example.com",
      smtp_port: 587,
      smtp_domain: "example.com",
      smtp_username: "smtp-user",
      smtp_password: "smtp-password-123",
      smtp_from_name: "Notae Team",
      smtp_from_email: "noreply@example.com"
    )
    user.reload

    expect(user.attributes_before_type_cast["openai_api_key"]).not_to eq("sk-test-abc123")
    expect(user.attributes_before_type_cast["smtp_username"]).not_to eq("smtp-user")
    expect(user.attributes_before_type_cast["smtp_password"]).not_to eq("smtp-password-123")
    expect(user.openai_api_key).to eq("sk-test-abc123")
    expect(user.smtp_username).to eq("smtp-user")
    expect(user.smtp_password).to eq("smtp-password-123")
  end

  it "configures active record encryption keys at boot" do
    encryption_config = Rails.application.config.active_record.encryption

    expect(encryption_config.primary_key).to be_present
    expect(encryption_config.deterministic_key).to be_present
    expect(encryption_config.key_derivation_salt).to be_present
  end

  it "fails closed when encryption keys are missing instead of raising" do
    user = described_class.new(email: "missing-encryption@example.com", password: "password123")
    configuration_error = ActiveRecord::Encryption::Errors::Configuration.new("Missing key")
    allow(user).to receive(:openai_api_key).and_raise(configuration_error)
    allow(user).to receive(:smtp_password).and_raise(configuration_error)

    expect(user.openai_api_key_configured?).to be(false)
    expect(user.masked_openai_api_key).to eq("Not configured")
    expect(user.masked_smtp_password).to eq("Not configured")
  end
end
